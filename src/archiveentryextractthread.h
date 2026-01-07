/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 *
 * Thread that extracts and writes a specific entry from a ZIP archive
 * directly to a device without intermediate extraction to disk.
 */

#ifndef ARCHIVEENTRYEXTRACTTHREAD_H
#define ARCHIVEENTRYEXTRACTTHREAD_H

#include "downloadextractthread.h"
#include "archiveentryiodevice.h"

class ArchiveEntryExtractThread : public DownloadExtractThread
{
    Q_OBJECT
public:
    /**
     * @brief Construct a thread that streams an entry from an archive to a device
     * @param archivePath Path to the archive file (ZIP, etc.)
     * @param entryName Name of the entry to extract
     * @param dst Destination device path
     * @param parent Parent QObject
     */
    explicit ArchiveEntryExtractThread(const QString &archivePath, const QString &entryName,
                                        const QByteArray &dst, QObject *parent = nullptr);
    virtual ~ArchiveEntryExtractThread();

protected:
    virtual void run() override;
    virtual ssize_t _on_read(struct archive *a, const void **buff) override;
    virtual int _on_close(struct archive *a) override;
    void _cancelExtract();
    void extractRawImageRun();

private:
    QString _archivePath;
    QString _entryName;
    ArchiveEntryIODevice *_archiveDevice = nullptr;
    char *_inputBuf = nullptr;
    size_t _inputBufSize = 0;
};

#endif // ARCHIVEENTRYEXTRACTTHREAD_H
