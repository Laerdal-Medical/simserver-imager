/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 *
 * QIODevice wrapper that reads a specific entry from a ZIP archive
 * without extracting to disk first. Provides streaming access to
 * archive contents.
 */

#ifndef ARCHIVEENTRYIODEVICE_H
#define ARCHIVEENTRYIODEVICE_H

#include <QIODevice>
#include <QString>
#include <QFile>

// Forward declarations for libarchive
struct archive;
struct archive_entry;

class ArchiveEntryIODevice : public QIODevice
{
    Q_OBJECT
public:
    /**
     * @brief Construct an IODevice that reads a specific entry from an archive
     * @param archivePath Path to the archive file (ZIP, etc.)
     * @param entryName Name of the entry to read from the archive
     * @param parent Parent QObject
     */
    explicit ArchiveEntryIODevice(const QString &archivePath, const QString &entryName, QObject *parent = nullptr);
    ~ArchiveEntryIODevice() override;

    /**
     * @brief Open the archive and seek to the target entry
     * @param mode Must be QIODevice::ReadOnly
     * @return true if archive opened and entry found
     */
    bool open(OpenMode mode) override;

    /**
     * @brief Close the archive
     */
    void close() override;

    /**
     * @brief Check if the device is sequential (yes, archives are)
     */
    bool isSequential() const override { return true; }

    /**
     * @brief Get the size of the entry (uncompressed)
     */
    qint64 size() const override { return _entrySize; }

    /**
     * @brief Get bytes available to read
     */
    qint64 bytesAvailable() const override;

    /**
     * @brief Check if at end of entry
     */
    bool atEnd() const override;

    /**
     * @brief Get the archive path
     */
    QString archivePath() const { return _archivePath; }

    /**
     * @brief Get the entry name
     */
    QString entryName() const { return _entryName; }

protected:
    qint64 readData(char *data, qint64 maxlen) override;
    qint64 writeData(const char *data, qint64 len) override;

private:
    QString _archivePath;
    QString _entryName;
    QFile _file;
    struct archive *_archive = nullptr;
    qint64 _entrySize = 0;
    qint64 _bytesRead = 0;
    bool _entryFound = false;
    bool _atEnd = false;

    // Buffer for archive reading
    char *_buffer = nullptr;
    static constexpr size_t BUFFER_SIZE = 65536;
};

#endif // ARCHIVEENTRYIODEVICE_H
