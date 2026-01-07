/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "archiveentryiodevice.h"
#include <archive.h>
#include <archive_entry.h>
#include <QDebug>
#include <QFileInfo>

ArchiveEntryIODevice::ArchiveEntryIODevice(const QString &archivePath, const QString &entryName, QObject *parent)
    : QIODevice(parent)
    , _archivePath(archivePath)
    , _entryName(entryName)
{
    _buffer = new char[BUFFER_SIZE];
}

ArchiveEntryIODevice::~ArchiveEntryIODevice()
{
    close();
    delete[] _buffer;
}

bool ArchiveEntryIODevice::open(OpenMode mode)
{
    if (mode != QIODevice::ReadOnly) {
        qWarning() << "ArchiveEntryIODevice: Only ReadOnly mode is supported";
        return false;
    }

    if (!QFile::exists(_archivePath)) {
        qWarning() << "ArchiveEntryIODevice: Archive file not found:" << _archivePath;
        return false;
    }

    // Initialize libarchive
    _archive = archive_read_new();
    archive_read_support_filter_all(_archive);
    archive_read_support_format_all(_archive);

    // Open the archive
    if (archive_read_open_filename(_archive, _archivePath.toUtf8().constData(), 10240) != ARCHIVE_OK) {
        qWarning() << "ArchiveEntryIODevice: Failed to open archive:" << archive_error_string(_archive);
        archive_read_free(_archive);
        _archive = nullptr;
        return false;
    }

    // Find the target entry
    struct archive_entry *entry;
    while (archive_read_next_header(_archive, &entry) == ARCHIVE_OK) {
        QString currentEntry = QString::fromUtf8(archive_entry_pathname(entry));

        // Match by full path or just filename
        QString baseName = QFileInfo(currentEntry).fileName();
        if (currentEntry == _entryName || baseName == _entryName) {
            _entrySize = archive_entry_size(entry);
            _entryFound = true;
            _bytesRead = 0;
            _atEnd = false;

            qDebug() << "ArchiveEntryIODevice: Found entry" << currentEntry << "size:" << _entrySize;

            QIODevice::open(mode);
            return true;
        }

        archive_read_data_skip(_archive);
    }

    qWarning() << "ArchiveEntryIODevice: Entry not found in archive:" << _entryName;
    archive_read_free(_archive);
    _archive = nullptr;
    return false;
}

void ArchiveEntryIODevice::close()
{
    if (_archive) {
        archive_read_free(_archive);
        _archive = nullptr;
    }
    _entryFound = false;
    _atEnd = true;
    _bytesRead = 0;
    _entrySize = 0;
    QIODevice::close();
}

qint64 ArchiveEntryIODevice::bytesAvailable() const
{
    if (!_entryFound || _atEnd) {
        return 0;
    }
    // For sequential devices, return a reasonable buffer size
    return BUFFER_SIZE + QIODevice::bytesAvailable();
}

bool ArchiveEntryIODevice::atEnd() const
{
    return _atEnd || !_entryFound;
}

qint64 ArchiveEntryIODevice::readData(char *data, qint64 maxlen)
{
    if (!_archive || !_entryFound || _atEnd) {
        return -1;
    }

    ssize_t bytesRead = archive_read_data(_archive, data, static_cast<size_t>(maxlen));

    if (bytesRead < 0) {
        qWarning() << "ArchiveEntryIODevice: Read error:" << archive_error_string(_archive);
        return -1;
    }

    if (bytesRead == 0) {
        _atEnd = true;
    }

    _bytesRead += bytesRead;
    return bytesRead;
}

qint64 ArchiveEntryIODevice::writeData(const char *data, qint64 len)
{
    Q_UNUSED(data);
    Q_UNUSED(len);
    // Read-only device
    return -1;
}
