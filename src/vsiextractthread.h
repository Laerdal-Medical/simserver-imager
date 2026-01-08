#ifndef VSIEXTRACTTHREAD_H
#define VSIEXTRACTTHREAD_H

/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 *
 * VSI (Versioned Sparse Image) extraction thread
 * Handles decompression and writing of Laerdal VSI format disk images
 */

#include "downloadextractthread.h"
#include <QFile>
#include <zlib.h>
#include <memory>

class VsiExtractThread : public DownloadExtractThread
{
    Q_OBJECT
public:
    static constexpr size_t VSI_HEADER_SIZE = 128;
    static constexpr char VSI_MAGIC[4] = {'V', 'S', 'I', '1'};

    // VSI header structure (little-endian, packed)
#pragma pack(push, 1)
    struct VsiHeader {
        char magic[4];           // "VSI1"
        int32_t blockSize;       // Block size in bytes
        int64_t uncompressedSize; // Total uncompressed image size
        uint8_t md5[16];         // MD5 checksum of compressed payload
        char label[64];          // Image label
        char version[28];        // Image version string
        int32_t timestamp;       // Unix timestamp
    };
#pragma pack(pop)

    explicit VsiExtractThread(const QByteArray &url, const QByteArray &dst = "",
                              const QByteArray &expectedHash = "", QObject *parent = nullptr);
    virtual ~VsiExtractThread();

    // Static method to parse VSI header from a file for size estimation
    static bool parseVsiHeader(const QString &filename, VsiHeader &header);
    static bool parseVsiHeader(QIODevice *device, VsiHeader &header);

protected:
    virtual void run() override;
    void extractVsiLocalRun();
    void extractVsiNetworkRun();

private:
    bool _parseHeader();
    bool _initZlib();
    void _cleanupZlib();
    bool _processDecompressedData(const char *data, size_t len);
    bool _flushWriteBuffer();
    void _appendToWriteBuffer(const char *data, size_t len);

    VsiHeader _header;
    z_stream _zstream;
    bool _zlibInitialized;

    // Decompression state
    QByteArray _decompressBuffer;
    QByteArray _pendingData;  // Partial block data waiting for more
    size_t _bytesInCurrentBlock;
    bool _expectingDelimiter;

    // Local file handling
    QFile _localFile;
    std::unique_ptr<char[]> _inputBuffer;
    size_t _inputBufferSize;

    // Page-aligned write buffer for Direct I/O compatibility
    char *_writeBuffer;         // Page-aligned buffer for writes
    size_t _writeBufferCapacity;
    size_t _writeBufferUsed;

    // Pre-allocated zero block (page-aligned)
    char *_zeroBlock;
    size_t _zeroBlockSize;

    // MD5 verification of compressed payload
    QByteArray _payloadMd5;

    // Progress tracking
    quint64 _totalBytesWritten;
};

#endif // VSIEXTRACTTHREAD_H
