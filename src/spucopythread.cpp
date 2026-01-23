/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "spucopythread.h"
#include "disk_format_helper.h"
#include "mount_helper.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QThread>
#include <QUrl>
#include <QStandardPaths>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QEventLoop>

#include <archive.h>
#include <archive_entry.h>

SPUCopyThread::SPUCopyThread(const QString &archivePath, const QString &spuEntry,
                             const QByteArray &device, bool skipFormat,
                             QObject *parent)
    : QThread(parent)
    , _archivePath(archivePath)
    , _spuEntry(spuEntry)
    , _device(device)
    , _skipFormat(skipFormat)
    , _isDirectFile(false)
    , _isUrlDownload(false)
    , _cancelled(false)
{
}

SPUCopyThread::SPUCopyThread(const QString &spuFilePath, const QByteArray &device,
                             bool skipFormat, QObject *parent)
    : QThread(parent)
    , _spuFilePath(spuFilePath)
    , _device(device)
    , _skipFormat(skipFormat)
    , _isDirectFile(true)
    , _isUrlDownload(false)
    , _cancelled(false)
{
}

SPUCopyThread::SPUCopyThread(const QUrl &url, const QByteArray &device,
                             bool skipFormat, QObject *parent)
    : QThread(parent)
    , _spuUrl(url)
    , _device(device)
    , _skipFormat(skipFormat)
    , _isDirectFile(false)
    , _isUrlDownload(true)
    , _cancelled(false)
{
}

SPUCopyThread::~SPUCopyThread()
{
    _cancelled = true;
    wait();
}

void SPUCopyThread::setAuthToken(const QString &token)
{
    _authToken = token;
}

void SPUCopyThread::setDownloadFilename(const QString &filename)
{
    _downloadFilename = filename;
}

void SPUCopyThread::cancelCopy()
{
    _cancelled = true;
}

void SPUCopyThread::run()
{
    qDebug() << "SPUCopyThread: Starting copy operation";
    qDebug() << "  Device:" << _device;
    qDebug() << "  Skip format:" << _skipFormat;

    if (_isUrlDownload)
    {
        qDebug() << "  SPU URL:" << _spuUrl;
    }
    else if (_isDirectFile)
    {
        qDebug() << "  SPU file:" << _spuFilePath;
    }
    else
    {
        qDebug() << "  Archive:" << _archivePath;
        qDebug() << "  SPU entry:" << _spuEntry;
    }

    // Step 0: Download from URL if needed
    if (_isUrlDownload)
    {
        emit preparationStatusUpdate(tr("Downloading SPU file..."));
        QString downloadedPath = downloadFromUrl();
        if (downloadedPath.isEmpty())
        {
            return; // Error already emitted
        }
        // Switch to direct file mode with the downloaded file
        _spuFilePath = downloadedPath;
        _isDirectFile = true;
        _isUrlDownload = false;
    }

    // Step 1: Format drive if needed
    if (!_skipFormat)
    {
        if (!formatDrive())
        {
            return; // Error already emitted
        }
    }
    else
    {
        qDebug() << "SPUCopyThread: Skipping format, using existing compatible filesystem";
    }

    if (_cancelled)
    {
        emit error(tr("Operation cancelled"));
        return;
    }

    // Step 2: Mount the drive
    emit preparationStatusUpdate(tr("Mounting USB drive..."));
    QString mountPoint = mountDrive();
    if (mountPoint.isEmpty())
    {
        emit error(tr("Failed to mount USB drive"));
        return;
    }

    qDebug() << "SPUCopyThread: Mounted at:" << mountPoint;

    if (_cancelled)
    {
        unmountDrive(mountPoint);
        emit error(tr("Operation cancelled"));
        return;
    }

    // Step 2.5: Delete existing SPU files if using existing filesystem
    if (_skipFormat)
    {
        emit preparationStatusUpdate(tr("Removing existing SPU files..."));
        deleteExistingSpuFiles(mountPoint);
    }

    if (_cancelled)
    {
        unmountDrive(mountPoint);
        emit error(tr("Operation cancelled"));
        return;
    }

    // Step 3: Copy SPU file
    emit preparationStatusUpdate(tr("Copying SPU file..."));
    bool copySuccess = false;

    if (_isDirectFile)
    {
        copySuccess = copyDirectFile(mountPoint);
    }
    else
    {
        copySuccess = extractAndCopy(mountPoint);
    }

    if (_cancelled)
    {
        unmountDrive(mountPoint);
        emit error(tr("Operation cancelled"));
        return;
    }

    if (!copySuccess)
    {
        unmountDrive(mountPoint);
        return; // Error already emitted
    }

    // Step 4: Unmount drive
    emit preparationStatusUpdate(tr("Safely ejecting USB drive..."));
    if (!unmountDrive(mountPoint))
    {
        emit error(tr("Failed to safely eject USB drive. Please wait and manually eject."));
        return;
    }

    qDebug() << "SPUCopyThread: Copy operation completed successfully";
    emit success();
}

bool SPUCopyThread::formatDrive()
{
    emit preparationStatusUpdate(tr("Formatting USB drive to FAT32..."));

    QString device = QString::fromLatin1(_device);
    auto result = DiskFormatHelper::formatDeviceFat32(device, "LAERDAL");

    if (!result.success)
    {
        emit error(result.errorMessage);
        return false;
    }

    emit preparationStatusUpdate(tr("Waiting for filesystem to be ready..."));
    return true;
}

QString SPUCopyThread::mountDrive()
{
    return MountHelper::mountDevice(QString::fromLatin1(_device));
}

bool SPUCopyThread::unmountDrive(const QString &mountPoint)
{
    return MountHelper::unmountDevice(mountPoint);
}

bool SPUCopyThread::extractAndCopy(const QString &mountPoint)
{
    qDebug() << "SPUCopyThread: Extracting" << _spuEntry << "from" << _archivePath;

    struct archive *a = archive_read_new();
    struct archive_entry *entry;

    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (archive_read_open_filename(a, _archivePath.toUtf8().constData(), 10240) != ARCHIVE_OK)
    {
        emit error(tr("Failed to open archive: %1").arg(QString::fromUtf8(archive_error_string(a))));
        archive_read_free(a);
        return false;
    }

    bool found = false;
    bool success = false;

    while (archive_read_next_header(a, &entry) == ARCHIVE_OK)
    {
        if (_cancelled)
        {
            break;
        }

        QString entryName = QString::fromUtf8(archive_entry_pathname(entry));

        // Check if this is the SPU file we're looking for
        if (entryName == _spuEntry || entryName.endsWith("/" + _spuEntry))
        {
            found = true;
            qint64 entrySize = archive_entry_size(entry);
            QString destPath = mountPoint + "/" + QFileInfo(_spuEntry).fileName();

            qDebug() << "SPUCopyThread: Found SPU entry, size:" << entrySize;
            qDebug() << "SPUCopyThread: Destination:" << destPath;

            QFile destFile(destPath);
            if (!destFile.open(QIODevice::WriteOnly))
            {
                emit error(tr("Failed to create file on USB drive: %1").arg(destFile.errorString()));
                break;
            }

            // Copy data with progress
            const size_t bufferSize = 1024 * 1024; // 1MB buffer
            char *buffer = new char[bufferSize];
            qint64 totalWritten = 0;

            while (!_cancelled)
            {
                ssize_t bytesRead = archive_read_data(a, buffer, bufferSize);
                if (bytesRead < 0)
                {
                    emit error(tr("Error reading from archive: %1").arg(QString::fromUtf8(archive_error_string(a))));
                    delete[] buffer;
                    destFile.close();
                    destFile.remove();
                    break;
                }
                if (bytesRead == 0)
                {
                    // End of entry
                    success = true;
                    break;
                }

                qint64 bytesWritten = destFile.write(buffer, bytesRead);
                if (bytesWritten != bytesRead)
                {
                    emit error(tr("Error writing to USB drive: %1").arg(destFile.errorString()));
                    delete[] buffer;
                    destFile.close();
                    destFile.remove();
                    break;
                }

                totalWritten += bytesWritten;
                emit copyProgress(totalWritten, entrySize);
            }

            delete[] buffer;
            destFile.flush();
            destFile.close();

            if (success)
            {
                qDebug() << "SPUCopyThread: Successfully copied" << totalWritten << "bytes";
            }

            break;
        }

        archive_read_data_skip(a);
    }

    archive_read_close(a);
    archive_read_free(a);

    if (!found && !_cancelled)
    {
        emit error(tr("SPU file '%1' not found in archive").arg(_spuEntry));
        return false;
    }

    return success;
}

bool SPUCopyThread::copyDirectFile(const QString &mountPoint)
{
    qDebug() << "SPUCopyThread: Copying direct file" << _spuFilePath;

    QFile srcFile(_spuFilePath);
    if (!srcFile.open(QIODevice::ReadOnly))
    {
        emit error(tr("Failed to open SPU file: %1").arg(srcFile.errorString()));
        return false;
    }

    qint64 totalSize = srcFile.size();
    // Use the download filename if set (to avoid temp file prefix in destination name)
    QString destFilename = _downloadFilename.isEmpty() ? QFileInfo(_spuFilePath).fileName() : _downloadFilename;
    QString destPath = mountPoint + "/" + destFilename;

    qDebug() << "SPUCopyThread: Destination:" << destPath;
    qDebug() << "SPUCopyThread: Size:" << totalSize;

    QFile destFile(destPath);
    if (!destFile.open(QIODevice::WriteOnly))
    {
        emit error(tr("Failed to create file on USB drive: %1").arg(destFile.errorString()));
        srcFile.close();
        return false;
    }

    // Copy with progress
    const size_t bufferSize = 1024 * 1024; // 1MB buffer
    char *buffer = new char[bufferSize];
    qint64 totalWritten = 0;
    bool success = true;

    while (!_cancelled && totalWritten < totalSize)
    {
        qint64 bytesRead = srcFile.read(buffer, bufferSize);
        if (bytesRead < 0)
        {
            emit error(tr("Error reading SPU file: %1").arg(srcFile.errorString()));
            success = false;
            break;
        }
        if (bytesRead == 0)
        {
            break; // EOF
        }

        qint64 bytesWritten = destFile.write(buffer, bytesRead);
        if (bytesWritten != bytesRead)
        {
            emit error(tr("Error writing to USB drive: %1").arg(destFile.errorString()));
            success = false;
            break;
        }

        totalWritten += bytesWritten;
        emit copyProgress(totalWritten, totalSize);
    }

    delete[] buffer;
    destFile.flush();
    destFile.close();
    srcFile.close();

    if (!success)
    {
        destFile.remove();
    }
    else
    {
        qDebug() << "SPUCopyThread: Successfully copied" << totalWritten << "bytes";
    }

    return success;
}

QString SPUCopyThread::downloadFromUrl()
{
    qDebug() << "SPUCopyThread: Downloading SPU from URL:" << _spuUrl;

    // Create temp directory for download
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    QString filename = _downloadFilename.isEmpty() ? _spuUrl.fileName() : _downloadFilename;
    if (filename.isEmpty())
    {
        filename = "downloaded.spu";
    }
    QString tempPath = tempDir + "/laerdal-spu-" + filename;

    qDebug() << "SPUCopyThread: Downloading to:" << tempPath;

    // Use synchronous download with event loop
    QNetworkAccessManager manager;
    QNetworkRequest request(_spuUrl);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    if (!_authToken.isEmpty()) {
        request.setRawHeader("Authorization", QString("token %1").arg(_authToken).toUtf8());
        request.setRawHeader("Accept", "application/octet-stream");
    }

    QNetworkReply *reply = manager.get(request);

    // Open file for writing
    QFile file(tempPath);
    if (!file.open(QIODevice::WriteOnly))
    {
        emit error(tr("Failed to create temporary file: %1").arg(file.errorString()));
        reply->deleteLater();
        return QString();
    }

    // Track download progress
    qint64 totalBytes = 0;
    qint64 receivedBytes = 0;

    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);

    connect(reply, &QNetworkReply::downloadProgress, reply,
            [this, &receivedBytes, &totalBytes](qint64 received, qint64 total) {
                receivedBytes = received;
                if (total > 0)
                {
                    totalBytes = total;
                    emit copyProgress(received, total);
                }
            });

    connect(reply, &QNetworkReply::readyRead, reply,
            [&file, reply]() {
                file.write(reply->readAll());
            });

    // Start the event loop
    loop.exec();

    // Write any remaining buffered data
    QByteArray remaining = reply->readAll();
    if (!remaining.isEmpty()) {
        file.write(remaining);
    }

    file.close();

    if (reply->error() != QNetworkReply::NoError)
    {
        emit error(tr("Download failed: %1").arg(reply->errorString()));
        file.remove();
        reply->deleteLater();
        return QString();
    }

    int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QString contentType = reply->header(QNetworkRequest::ContentTypeHeader).toString();
    QUrl finalUrl = reply->url();
    qDebug() << "SPUCopyThread: HTTP status:" << httpStatus << "Content-Type:" << contentType;
    qDebug() << "SPUCopyThread: Final URL:" << finalUrl;

    reply->deleteLater();

    qDebug() << "SPUCopyThread: Download complete, size:" << QFileInfo(tempPath).size();
    return tempPath;
}

void SPUCopyThread::deleteExistingSpuFiles(const QString &mountPoint)
{
    qDebug() << "SPUCopyThread: Deleting existing SPU files from:" << mountPoint;

    QDir dir(mountPoint);
    QStringList spuFiles = dir.entryList({"*.spu", "*.SPU"}, QDir::Files);

    for (const QString &filename : spuFiles)
    {
        QString filePath = mountPoint + "/" + filename;
        qDebug() << "SPUCopyThread: Deleting:" << filePath;

        if (!QFile::remove(filePath))
        {
            qWarning() << "SPUCopyThread: Failed to delete:" << filePath;
        }
    }

    qDebug() << "SPUCopyThread: Deleted" << spuFiles.count() << "SPU file(s)";
}
