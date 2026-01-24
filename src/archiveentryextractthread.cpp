/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "archiveentryextractthread.h"
#include "systemmemorymanager.h"
#include <archive.h>
#include <archive_entry.h>
#include <QDebug>
#include <QFileInfo>

ArchiveEntryExtractThread::ArchiveEntryExtractThread(const QString &archivePath, const QString &entryName,
                                                      const QByteArray &dst, QObject *parent)
    : DownloadExtractThread(QByteArray(), dst, QByteArray(), parent)
    , _archivePath(archivePath)
    , _entryName(entryName)
{
    // Use optimal buffer sizing for better performance
    size_t bufferSize = SystemMemoryManager::instance().getOptimalWriteBufferSize();
    _inputBuf = static_cast<char*>(qMallocAligned(bufferSize, 4096));
    _inputBufSize = bufferSize;

    qDebug() << "ArchiveEntryExtractThread: Created for" << archivePath << "entry:" << entryName;
}

ArchiveEntryExtractThread::~ArchiveEntryExtractThread()
{
    _cancelled = true;

    if (_archiveDevice) {
        _archiveDevice->close();
        delete _archiveDevice;
        _archiveDevice = nullptr;
    }

    wait();

    if (_inputBuf) {
        qFreeAligned(_inputBuf);
        _inputBuf = nullptr;
    }
}

void ArchiveEntryExtractThread::_cancelExtract()
{
    _cancelled = true;
    if (_archiveDevice && _archiveDevice->isOpen()) {
        _archiveDevice->close();
    }
}

void ArchiveEntryExtractThread::run()
{
    _allocateBuffers();

    if (isImage() && !_openAndPrepareDevice()) {
        return;
    }

    emit preparationStatusUpdate(tr("Opening archive entry..."));
    _timer.start();

    // Open the archive entry device to stream data from the outer ZIP
    _archiveDevice = new ArchiveEntryIODevice(_archivePath, _entryName);
    if (!_archiveDevice->open(QIODevice::ReadOnly)) {
        _onDownloadError(tr("Failed to open entry '%1' in archive").arg(_entryName));
        _closeFiles();
        return;
    }

    _lastDlTotal = _archiveDevice->size();
    qDebug() << "ArchiveEntryExtractThread: Entry size (compressed):" << _lastDlTotal;

    emit preparationStatusUpdate(tr("Writing image..."));

    // Check if the entry is compressed (e.g., .wic.gz, .wic.xz)
    QString lowerName = _entryName.toLower();
    bool isCompressed = lowerName.endsWith(".gz") || lowerName.endsWith(".xz") ||
                        lowerName.endsWith(".zst") || lowerName.endsWith(".bz2") ||
                        lowerName.endsWith(".lz4");

    if (isCompressed) {
        // Use libarchive to decompress while streaming
        qDebug() << "ArchiveEntryExtractThread: Entry is compressed, using libarchive for decompression";
        extractImageRun();  // Uses _on_read callback which reads from _archiveDevice
    } else {
        // Raw WIC file - stream directly
        qDebug() << "ArchiveEntryExtractThread: Entry is uncompressed, streaming directly";
        extractRawImageRun();
    }

    if (_cancelled) {
        _closeFiles();
    }
}

void ArchiveEntryExtractThread::extractRawImageRun()
{
    qDebug() << "ArchiveEntryExtractThread: Streaming raw image from archive entry";

    qint64 totalBytes = _archiveDevice->size();
    qint64 bytesWritten = 0;

    while (!_archiveDevice->atEnd() && !_cancelled) {
        qint64 len = _archiveDevice->read(_inputBuf, static_cast<qint64>(_inputBufSize));

        if (len < 0) {
            _onDownloadError(tr("Error reading from archive entry"));
            break;
        }

        if (len == 0) {
            break;  // End of entry
        }

        // Write the data directly to the output device
        size_t written = _writeFile(_inputBuf, len);
        if (written != static_cast<size_t>(len)) {
            _onDownloadError(tr("Error writing to device"));
            break;
        }

        bytesWritten += len;
        _lastDlNow = bytesWritten;

        // Emit progress updates
        _emitProgressUpdate();
    }

    if (!_cancelled && (totalBytes == 0 || bytesWritten >= totalBytes)) {
        qDebug() << "ArchiveEntryExtractThread: Write completed, bytes written:" << bytesWritten;
        _writeComplete();
    } else if (!_cancelled) {
        _onDownloadError(tr("Failed to read complete archive entry"));
    }
}

ssize_t ArchiveEntryExtractThread::_on_read(struct archive *, const void **buff)
{
    if (_cancelled || !_archiveDevice) {
        return -1;
    }

    *buff = _inputBuf;
    ssize_t len = _archiveDevice->read(_inputBuf, static_cast<qint64>(_inputBufSize));

    if (len > 0) {
        _lastDlNow += len;
        _emitProgressUpdate();
    }

    return len;
}

int ArchiveEntryExtractThread::_on_close(struct archive *)
{
    if (_archiveDevice) {
        _archiveDevice->close();
    }
    return 0;
}
