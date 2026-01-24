/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "downloadarchiveextractthread.h"
#include <archive.h>
#include <archive_entry.h>
#include <QDebug>
#include <QElapsedTimer>
#include <stdexcept>
#include <cstring>

using namespace std;

static inline void _checkArchiveResult(int r, struct archive *a)
{
    if (r == ARCHIVE_FATAL)
    {
        throw runtime_error(archive_error_string(a));
    }
    if (r < ARCHIVE_OK)
    {
        qDebug() << archive_error_string(a);
    }
}

DownloadArchiveExtractThread::DownloadArchiveExtractThread(const QByteArray &url, const QByteArray &localfilename,
                                                           const QByteArray &expectedHash, QObject *parent)
    : DownloadExtractThread(url, localfilename, expectedHash, parent)
{
}

void DownloadArchiveExtractThread::setTargetEntry(const QString &entryName)
{
    _targetEntry = entryName;
}

bool DownloadArchiveExtractThread::_isCompressedEntry(const QString &entryName)
{
    QString lower = entryName.toLower();
    return lower.endsWith(".xz") || lower.endsWith(".gz") || lower.endsWith(".zst")
           || lower.endsWith(".bz2") || lower.endsWith(".lz4");
}

ssize_t DownloadArchiveExtractThread::_inner_archive_read(struct archive *, void *client_data, const void **buff)
{
    auto *ctx = static_cast<InnerReadContext *>(client_data);

    ssize_t bytesRead = archive_read_data(ctx->outerArchive, ctx->buffer, ctx->bufferCapacity);
    if (bytesRead < 0)
    {
        return ARCHIVE_FATAL;
    }

    *buff = ctx->buffer;
    return bytesRead;
}

int DownloadArchiveExtractThread::_inner_archive_close(struct archive *, void *)
{
    return ARCHIVE_OK;
}

void DownloadArchiveExtractThread::extractImageRun()
{
    QElapsedTimer extractionTimer;
    extractionTimer.start();

    // Outer archive: reads ZIP from input ring buffer
    struct archive *outerArchive = archive_read_new();
    struct archive_entry *entry;

    archive_read_support_filter_all(outerArchive);
    archive_read_support_format_all(outerArchive);

    archive_read_open(outerArchive, this, NULL,
                      &DownloadExtractThread::_archive_read,
                      &DownloadExtractThread::_archive_close);

    try
    {
        bool found = false;

        while (archive_read_next_header(outerArchive, &entry) == ARCHIVE_OK)
        {
            if (_cancelled) break;

            QString entryName = QString::fromUtf8(archive_entry_pathname(entry));
            qint64 entrySize = archive_entry_size(entry);

            qDebug() << "DownloadArchiveExtractThread: ZIP entry:" << entryName << "size:" << entrySize;

            // Match target entry: exact match or filename-only match
            bool matches = false;
            if (!_targetEntry.isEmpty())
            {
                matches = (entryName == _targetEntry) ||
                          entryName.endsWith("/" + _targetEntry) ||
                          (entryName.section('/', -1) == _targetEntry);
            }
            else
            {
                // No target specified: find first WIC file
                QString lower = entryName.toLower();
                matches = lower.endsWith(".wic") || lower.contains(".wic.");
            }

            if (matches)
            {
                found = true;
                emit entryDiscovered(entryName, entrySize);
                qDebug() << "DownloadArchiveExtractThread: Found target entry:" << entryName;

                emit eventImageExtraction(static_cast<quint32>(extractionTimer.elapsed()), true);

                if (_isCompressedEntry(entryName))
                {
                    qDebug() << "DownloadArchiveExtractThread: Entry is compressed, using two-stage decompression";
                    _extractCompressedEntry(outerArchive);
                }
                else
                {
                    qDebug() << "DownloadArchiveExtractThread: Entry is uncompressed, direct extraction";
                    _extractUncompressedEntry(outerArchive);
                }
                break;
            }

            archive_read_data_skip(outerArchive);
        }

        if (!found && !_cancelled)
        {
            QString msg = _targetEntry.isEmpty()
                              ? tr("No WIC image found in archive")
                              : tr("Entry '%1' not found in archive").arg(_targetEntry);
            DownloadThread::cancelDownload();
            emit error(msg);
        }
    }
    catch (exception &e)
    {
        if (_file && _file->IsAsyncIOSupported())
        {
            _file->WaitForPendingWrites();
        }

        if (!_cancelled)
        {
            DownloadThread::cancelDownload();
            emit error(tr("Error extracting archive: %1").arg(e.what()));
        }
    }

    archive_read_free(outerArchive);

    // Emit pipeline timing summary
    emit eventPipelineDecompressionTime(
        static_cast<quint32>(_totalDecompressionMs.load()),
        _bytesDecompressed.load());
    emit eventPipelineRingBufferWaitTime(
        static_cast<quint32>(_totalRingBufferWaitMs.load()),
        _bytesReadFromRingBuffer.load());

    qDebug() << "DownloadArchiveExtractThread: Pipeline timing:"
             << "decompress=" << _totalDecompressionMs.load() << "ms"
             << "(ring_wait=" << _totalRingBufferWaitMs.load() << "ms)";

    if (_writeRingBuffer)
    {
        uint64_t producerStalls, consumerStalls, producerWaitMs, consumerWaitMs;
        _writeRingBuffer->getStarvationStats(producerStalls, consumerStalls, producerWaitMs, consumerWaitMs);
        if (producerStalls > 0 || consumerStalls > 0)
        {
            qDebug() << "Write ring buffer stats:"
                     << "producer stalls:" << producerStalls << "(" << producerWaitMs << "ms),"
                     << "consumer stalls:" << consumerStalls << "(" << consumerWaitMs << "ms)";
        }
        emit eventWriteRingBufferStats(producerStalls, consumerStalls, producerWaitMs, consumerWaitMs);
    }
}

void DownloadArchiveExtractThread::_extractCompressedEntry(struct archive *outerArchive)
{
    // Allocate intermediate buffer for outer → inner data transfer
    const size_t innerBufSize = 256 * 1024; // 256KB chunks
    char *innerBuf = new char[innerBufSize];

    InnerReadContext ctx;
    ctx.outerArchive = outerArchive;
    ctx.buffer = innerBuf;
    ctx.bufferCapacity = innerBufSize;

    // Inner archive: decompresses entry data (xz/gz/zst/bz2)
    struct archive *innerArchive = archive_read_new();
    struct archive_entry *innerEntry;

    archive_read_support_filter_all(innerArchive);
    archive_read_support_format_raw(innerArchive);

    _configureArchiveOptions(innerArchive);

    int r = archive_read_open(innerArchive, &ctx, NULL,
                              &DownloadArchiveExtractThread::_inner_archive_read,
                              &DownloadArchiveExtractThread::_inner_archive_close);
    if (r != ARCHIVE_OK)
    {
        delete[] innerBuf;
        archive_read_free(innerArchive);
        throw runtime_error(std::string("Failed to open inner archive: ") + archive_error_string(innerArchive));
    }

    r = archive_read_next_header(innerArchive, &innerEntry);
    _checkArchiveResult(r, innerArchive);

    _logCompressionFilters(innerArchive);

    QElapsedTimer decompressTimer;

    // Read decompressed data into write ring buffer slots
    while (!_cancelled)
    {
        RingBuffer::Slot *slot = _writeRingBuffer->acquireWriteSlot(100);
        while (!slot && !_cancelled && !_writeRingBuffer->isCancelled())
        {
            slot = _writeRingBuffer->acquireWriteSlot(100);
        }
        if (!slot)
        {
            if (_cancelled) break;
            throw runtime_error("Failed to acquire write buffer slot");
        }

        decompressTimer.start();
        ssize_t size = archive_read_data(innerArchive, slot->data, slot->capacity);
        _totalDecompressionMs.fetch_add(static_cast<quint64>(decompressTimer.elapsed()));

        if (size < 0)
        {
            const char *errorStr = archive_error_string(innerArchive);
            _writeRingBuffer->releaseReadSlot(slot);

            if (size == ARCHIVE_FATAL && errorStr && strstr(errorStr, "No progress is possible"))
            {
                break;
            }
            throw runtime_error(errorStr);
        }
        if (size == 0)
        {
            _writeRingBuffer->releaseReadSlot(slot);
            break;
        }

        // Pad to sector boundary
        if (size % 512 != 0)
        {
            size_t paddingBytes = 512 - (size % 512);
            memset(slot->data + size, 0, paddingBytes);
            size += paddingBytes;
        }

        _bytesDecompressed.fetch_add(static_cast<quint64>(size));
        _emitProgressUpdate();

        RingBuffer *ringBuf = _writeRingBuffer.get();
        RingBuffer::Slot *slotToRelease = slot;
        DownloadThread::WriteCompleteCallback releaseCallback = [ringBuf, slotToRelease]() {
            ringBuf->releaseReadSlot(slotToRelease);
        };

        bool writeOk = _writeFile(slot->data, static_cast<size_t>(size), releaseCallback) > 0;
        if (!writeOk && !_cancelled)
        {
            if (_file && _file->IsAsyncIOSupported())
            {
                _file->WaitForPendingWrites();
            }
            _onWriteError();
            archive_read_free(innerArchive);
            delete[] innerBuf;
            return;
        }
    }

    _writeComplete();

    archive_read_free(innerArchive);
    delete[] innerBuf;
}

void DownloadArchiveExtractThread::_extractUncompressedEntry(struct archive *outerArchive)
{
    QElapsedTimer decompressTimer;

    // Read directly from outer archive into write ring buffer slots
    while (!_cancelled)
    {
        RingBuffer::Slot *slot = _writeRingBuffer->acquireWriteSlot(100);
        while (!slot && !_cancelled && !_writeRingBuffer->isCancelled())
        {
            slot = _writeRingBuffer->acquireWriteSlot(100);
        }
        if (!slot)
        {
            if (_cancelled) break;
            throw runtime_error("Failed to acquire write buffer slot");
        }

        decompressTimer.start();
        ssize_t size = archive_read_data(outerArchive, slot->data, slot->capacity);
        _totalDecompressionMs.fetch_add(static_cast<quint64>(decompressTimer.elapsed()));

        if (size < 0)
        {
            const char *errorStr = archive_error_string(outerArchive);
            _writeRingBuffer->releaseReadSlot(slot);

            if (size == ARCHIVE_FATAL && errorStr && strstr(errorStr, "No progress is possible"))
            {
                break;
            }
            throw runtime_error(errorStr);
        }
        if (size == 0)
        {
            _writeRingBuffer->releaseReadSlot(slot);
            break;
        }

        // Pad to sector boundary
        if (size % 512 != 0)
        {
            size_t paddingBytes = 512 - (size % 512);
            memset(slot->data + size, 0, paddingBytes);
            size += paddingBytes;
        }

        _bytesDecompressed.fetch_add(static_cast<quint64>(size));
        _emitProgressUpdate();

        RingBuffer *ringBuf = _writeRingBuffer.get();
        RingBuffer::Slot *slotToRelease = slot;
        DownloadThread::WriteCompleteCallback releaseCallback = [ringBuf, slotToRelease]() {
            ringBuf->releaseReadSlot(slotToRelease);
        };

        bool writeOk = _writeFile(slot->data, static_cast<size_t>(size), releaseCallback) > 0;
        if (!writeOk && !_cancelled)
        {
            if (_file && _file->IsAsyncIOSupported())
            {
                _file->WaitForPendingWrites();
            }
            _onWriteError();
            return;
        }
    }

    _writeComplete();
}
