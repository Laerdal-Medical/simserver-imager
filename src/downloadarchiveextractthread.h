#ifndef DOWNLOADARCHIVEEXTRACTTHREAD_H
#define DOWNLOADARCHIVEEXTRACTTHREAD_H

/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "downloadextractthread.h"

struct archive;

/*
 * Downloads a ZIP archive and extracts a single WIC image entry from it,
 * optionally decompressing the entry if it's compressed (.xz, .gz, .zst, .bz2).
 *
 * Pipeline:
 *   curl → [Input Ring Buffer] → ZIP extract (libarchive #1) →
 *     if compressed: decompress (libarchive #2) → [Write Ring Buffer] → device
 *     if uncompressed: → [Write Ring Buffer] → device
 *
 * Used for CI artifact streaming where the artifact is a ZIP containing
 * a single .wic or .wic.xz file.
 */
class DownloadArchiveExtractThread : public DownloadExtractThread
{
    Q_OBJECT
public:
    explicit DownloadArchiveExtractThread(const QByteArray &url, const QByteArray &localfilename = "",
                                          const QByteArray &expectedHash = "", QObject *parent = nullptr);

    void setTargetEntry(const QString &entryName);

    virtual void extractImageRun() override;

signals:
    void entryDiscovered(QString name, qint64 size);

private:
    QString _targetEntry;

    // Context for feeding outer archive entry data to inner decompression archive
    struct InnerReadContext {
        struct archive *outerArchive;
        char *buffer;
        size_t bufferCapacity;
    };

    static ssize_t _inner_archive_read(struct archive *a, void *client_data, const void **buff);
    static int _inner_archive_close(struct archive *a, void *client_data);

    bool _isCompressedEntry(const QString &entryName);
    void _extractCompressedEntry(struct archive *outerArchive);
    void _extractUncompressedEntry(struct archive *outerArchive);
};

#endif // DOWNLOADARCHIVEEXTRACTTHREAD_H
