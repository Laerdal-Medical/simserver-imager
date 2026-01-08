/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 *
 * VSI (Versioned Sparse Image) extraction thread implementation
 */

#include "vsiextractthread.h"
#include "config.h"
#include "systemmemorymanager.h"

#include <QUrl>
#include <QDebug>
#include <QCryptographicHash>
#include <cstring>

// Page alignment for Direct I/O
static constexpr size_t PAGE_ALIGNMENT = 4096;

VsiExtractThread::VsiExtractThread(const QByteArray &url, const QByteArray &dst,
                                   const QByteArray &expectedHash, QObject *parent)
    : DownloadExtractThread(url, dst, expectedHash, parent)
    , _zlibInitialized(false)
    , _bytesInCurrentBlock(0)
    , _expectingDelimiter(true)
    , _writeBuffer(nullptr)
    , _writeBufferCapacity(0)
    , _writeBufferUsed(0)
    , _zeroBlock(nullptr)
    , _zeroBlockSize(0)
    , _totalBytesWritten(0)
{
    std::memset(&_header, 0, sizeof(_header));
    std::memset(&_zstream, 0, sizeof(_zstream));

    // Allocate input buffer for local file reads
    size_t bufferSize = SystemMemoryManager::instance().getOptimalWriteBufferSize();
    _inputBuffer = std::make_unique<char[]>(bufferSize);
    _inputBufferSize = bufferSize;

    // Reserve space for decompression buffer
    _decompressBuffer.reserve(bufferSize);
}

VsiExtractThread::~VsiExtractThread()
{
    _cancelled = true;
    _cleanupZlib();

    if (_localFile.isOpen()) {
        _localFile.close();
    }

    // Free aligned buffers
    if (_writeBuffer) {
        qFreeAligned(_writeBuffer);
        _writeBuffer = nullptr;
    }
    if (_zeroBlock) {
        qFreeAligned(_zeroBlock);
        _zeroBlock = nullptr;
    }

    wait();
}

bool VsiExtractThread::parseVsiHeader(const QString &filename, VsiHeader &header)
{
    QFile file(filename);
    if (!file.open(QIODevice::ReadOnly)) {
        return false;
    }
    return parseVsiHeader(&file, header);
}

bool VsiExtractThread::parseVsiHeader(QIODevice *device, VsiHeader &header)
{
    if (device->read(reinterpret_cast<char*>(&header), sizeof(header)) != sizeof(header)) {
        qWarning() << "VsiExtractThread: Failed to read VSI header";
        return false;
    }

    // Validate magic
    if (std::memcmp(header.magic, VSI_MAGIC, 4) != 0) {
        qWarning() << "VsiExtractThread: Invalid VSI magic bytes";
        return false;
    }

    // Validate block size (must be positive and reasonable)
    if (header.blockSize <= 0 || header.blockSize > 64 * 1024 * 1024) {
        qWarning() << "VsiExtractThread: Invalid block size:" << header.blockSize;
        return false;
    }

    // Validate uncompressed size
    if (header.uncompressedSize <= 0) {
        qWarning() << "VsiExtractThread: Invalid uncompressed size:" << header.uncompressedSize;
        return false;
    }

    qDebug() << "VsiExtractThread: Parsed VSI header:"
             << "blockSize=" << header.blockSize
             << "uncompressedSize=" << header.uncompressedSize
             << "label=" << QString::fromLatin1(header.label, strnlen(header.label, sizeof(header.label)))
             << "version=" << QString::fromLatin1(header.version, strnlen(header.version, sizeof(header.version)));

    return true;
}

bool VsiExtractThread::_parseHeader()
{
    return parseVsiHeader(&_localFile, _header);
}

bool VsiExtractThread::_initZlib()
{
    if (_zlibInitialized) {
        return true;
    }

    _zstream.zalloc = Z_NULL;
    _zstream.zfree = Z_NULL;
    _zstream.opaque = Z_NULL;
    _zstream.avail_in = 0;
    _zstream.next_in = Z_NULL;

    int ret = inflateInit(&_zstream);
    if (ret != Z_OK) {
        qWarning() << "VsiExtractThread: Failed to initialize zlib:" << ret;
        return false;
    }

    _zlibInitialized = true;
    return true;
}

void VsiExtractThread::_cleanupZlib()
{
    if (_zlibInitialized) {
        inflateEnd(&_zstream);
        _zlibInitialized = false;
    }
}

void VsiExtractThread::run()
{
    QString urlStr = QString::fromLatin1(_url);
    bool isLocal = urlStr.startsWith("file://", Qt::CaseInsensitive);

    qDebug() << "VsiExtractThread starting. isImage?" << isImage() << "filename:" << _filename << "url:" << _url;

    if (isImage() && !_openAndPrepareDevice()) {
        return;
    }

    if (isLocal) {
        extractVsiLocalRun();
    } else {
        extractVsiNetworkRun();
    }

    if (_cancelled) {
        _closeFiles();
    }
}

void VsiExtractThread::_appendToWriteBuffer(const char *data, size_t len)
{
    // Copy data to the write buffer
    std::memcpy(_writeBuffer + _writeBufferUsed, data, len);
    _writeBufferUsed += len;
}

bool VsiExtractThread::_flushWriteBuffer()
{
    if (_writeBufferUsed == 0) {
        return true;
    }

    // Write the buffer contents
    size_t written = _writeFile(_writeBuffer, _writeBufferUsed);
    if (written != _writeBufferUsed) {
        qWarning() << "VsiExtractThread: Write failed - expected:" << _writeBufferUsed << "written:" << written;
        return false;
    }

    _writeBufferUsed = 0;
    return true;
}

void VsiExtractThread::extractVsiLocalRun()
{
    emit preparationStatusUpdate(tr("Opening VSI image file..."));
    _timer.start();

    _localFile.setFileName(QUrl(_url).toLocalFile());
    if (!_localFile.open(QIODevice::ReadOnly)) {
        _onDownloadError(tr("Error opening VSI file"));
        _closeFiles();
        return;
    }

    _lastDlTotal = _localFile.size();

    // Parse VSI header
    if (!_parseHeader()) {
        _onDownloadError(tr("Invalid VSI file format"));
        _closeFiles();
        return;
    }

    // Initialize zlib decompressor
    if (!_initZlib()) {
        _onDownloadError(tr("Failed to initialize decompressor"));
        _closeFiles();
        return;
    }

    // Allocate page-aligned write buffer for Direct I/O compatibility
    // Use a large buffer (8MB) to reduce number of write calls
    _writeBufferCapacity = 8 * 1024 * 1024;  // 8MB
    _writeBuffer = static_cast<char*>(qMallocAligned(_writeBufferCapacity, PAGE_ALIGNMENT));
    if (!_writeBuffer) {
        _onDownloadError(tr("Failed to allocate write buffer"));
        _cleanupZlib();
        _closeFiles();
        return;
    }
    _writeBufferUsed = 0;

    // Allocate page-aligned zero block for sparse writes
    // Round up block size to page alignment for Direct I/O
    _zeroBlockSize = ((_header.blockSize + PAGE_ALIGNMENT - 1) / PAGE_ALIGNMENT) * PAGE_ALIGNMENT;
    _zeroBlock = static_cast<char*>(qMallocAligned(_zeroBlockSize, PAGE_ALIGNMENT));
    if (!_zeroBlock) {
        _onDownloadError(tr("Failed to allocate zero block"));
        _cleanupZlib();
        _closeFiles();
        return;
    }
    std::memset(_zeroBlock, 0, _zeroBlockSize);

    // MD5 hash for payload verification
    QCryptographicHash payloadHash(QCryptographicHash::Md5);

    emit preparationStatusUpdate(tr("Extracting VSI image..."));

    // Allocate decompression output buffer
    size_t decompBufSize = _header.blockSize * 4;  // Process multiple blocks at once
    _decompressBuffer.resize(decompBufSize);

    qint64 compressedBytesRead = 0;
    bool finished = false;

    while (!_cancelled && !finished) {
        // Read compressed data
        qint64 bytesRead = _localFile.read(_inputBuffer.get(), _inputBufferSize);
        if (bytesRead < 0) {
            _onDownloadError(tr("Error reading VSI file"));
            break;
        }

        if (bytesRead == 0) {
            // EOF - finalize decompression
            finished = true;
        }

        compressedBytesRead += bytesRead;
        _lastDlNow = VSI_HEADER_SIZE + compressedBytesRead;

        // Update payload hash
        payloadHash.addData(QByteArrayView(_inputBuffer.get(), bytesRead));

        // Setup zlib input
        _zstream.avail_in = bytesRead;
        _zstream.next_in = reinterpret_cast<Bytef*>(_inputBuffer.get());

        // Decompress loop
        do {
            _zstream.avail_out = decompBufSize;
            _zstream.next_out = reinterpret_cast<Bytef*>(_decompressBuffer.data());

            int ret = inflate(&_zstream, finished ? Z_FINISH : Z_NO_FLUSH);

            if (ret == Z_STREAM_ERROR || ret == Z_DATA_ERROR || ret == Z_MEM_ERROR) {
                _onDownloadError(tr("Decompression error: %1").arg(ret));
                _cleanupZlib();
                _closeFiles();
                return;
            }

            size_t decompressedBytes = decompBufSize - _zstream.avail_out;
            if (decompressedBytes > 0) {
                _bytesDecompressed += decompressedBytes;

                if (!_processDecompressedData(_decompressBuffer.constData(), decompressedBytes)) {
                    _cleanupZlib();
                    _closeFiles();
                    return;
                }
            }

            if (ret == Z_STREAM_END) {
                finished = true;
                break;
            }

        } while (_zstream.avail_out == 0 && !_cancelled);

        // Emit progress
        _emitProgressUpdate();
    }

    // Flush any remaining data in the write buffer
    if (!_cancelled && !_flushWriteBuffer()) {
        _onDownloadError(tr("Error writing final data to device"));
        _cleanupZlib();
        _closeFiles();
        return;
    }

    _cleanupZlib();

    if (_cancelled) {
        return;
    }

    // Verify MD5 checksum
    QByteArray computedMd5 = payloadHash.result();
    QByteArray expectedMd5 = QByteArray(reinterpret_cast<const char*>(_header.md5), 16);

    if (computedMd5 != expectedMd5) {
        qWarning() << "VsiExtractThread: MD5 mismatch - expected:" << expectedMd5.toHex()
                   << "computed:" << computedMd5.toHex();
        _onDownloadError(tr("VSI file checksum verification failed"));
        _closeFiles();
        return;
    }

    qDebug() << "VsiExtractThread: MD5 verification passed";

    // Verify we wrote the expected amount
    if (_totalBytesWritten != static_cast<quint64>(_header.uncompressedSize)) {
        qWarning() << "VsiExtractThread: Size mismatch - expected:" << _header.uncompressedSize
                   << "written:" << _totalBytesWritten;
        _onDownloadError(tr("VSI extraction size mismatch"));
        _closeFiles();
        return;
    }

    qDebug() << "VsiExtractThread: Extraction completed successfully,"
             << _totalBytesWritten << "bytes written";

    _writeComplete();
}

void VsiExtractThread::extractVsiNetworkRun()
{
    // For network downloads, we need to buffer the header first,
    // then stream the rest through the ring buffer system.
    // This is more complex - for now, download to temp file first
    // and use local extraction.

    // TODO: Implement true streaming network extraction
    // For now, fall back to downloading the complete file first

    qDebug() << "VsiExtractThread: Network VSI extraction not yet implemented, using download+extract";

    // Use parent class download mechanism
    DownloadExtractThread::run();
}

bool VsiExtractThread::_processDecompressedData(const char *data, size_t len)
{
    size_t offset = 0;

    // If we have pending data from previous call, prepend it
    if (!_pendingData.isEmpty()) {
        _pendingData.append(data, len);
        data = _pendingData.constData();
        len = _pendingData.size();
    }

    while (offset < len && !_cancelled) {
        if (_expectingDelimiter) {
            // Read the delimiter byte
            uint8_t delim = static_cast<uint8_t>(data[offset]);
            offset++;

            if (delim == 0x00) {
                // Sparse block - append zeros to write buffer
                // Check if we need to flush first
                if (_writeBufferUsed + _header.blockSize > _writeBufferCapacity) {
                    if (!_flushWriteBuffer()) {
                        return false;
                    }
                }
                // Append zeros (use the pre-allocated zero block)
                _appendToWriteBuffer(_zeroBlock, _header.blockSize);
                _totalBytesWritten += _header.blockSize;
            } else if (delim == 0x01) {
                // Data block - need to read blockSize bytes
                _expectingDelimiter = false;
                _bytesInCurrentBlock = 0;
            } else {
                qWarning() << "VsiExtractThread: Invalid delimiter:" << delim;
                _onDownloadError(tr("Invalid VSI data format"));
                return false;
            }
        } else {
            // Reading data block content
            size_t remaining = _header.blockSize - _bytesInCurrentBlock;
            size_t available = len - offset;
            size_t toAppend = qMin(remaining, available);

            // Check if we need to flush first
            if (_writeBufferUsed + toAppend > _writeBufferCapacity) {
                if (!_flushWriteBuffer()) {
                    return false;
                }
            }

            // Append data to write buffer
            _appendToWriteBuffer(data + offset, toAppend);

            offset += toAppend;
            _bytesInCurrentBlock += toAppend;
            _totalBytesWritten += toAppend;

            if (_bytesInCurrentBlock == static_cast<size_t>(_header.blockSize)) {
                // Block complete, expect next delimiter
                _expectingDelimiter = true;
                _bytesInCurrentBlock = 0;
            }
        }
    }

    // Store any remaining data for next call
    if (offset < len) {
        _pendingData = QByteArray(data + offset, len - offset);
    } else {
        _pendingData.clear();
    }

    // Clear the prepended data if we consumed it all
    if (!_pendingData.isEmpty() && data == _pendingData.constData()) {
        _pendingData.clear();
    }

    return true;
}
