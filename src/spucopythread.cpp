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
    , _isArtifactStreaming(false)
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
    , _isArtifactStreaming(false)
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
    , _isArtifactStreaming(false)
    , _cancelled(false)
{
}

SPUCopyThread::SPUCopyThread(const QUrl &artifactUrl, const QString &targetEntry,
                             const QByteArray &device, bool skipFormat,
                             QObject *parent)
    : QThread(parent)
    , _spuUrl(artifactUrl)
    , _artifactEntry(targetEntry)
    , _device(device)
    , _skipFormat(skipFormat)
    , _isDirectFile(false)
    , _isUrlDownload(false)
    , _isArtifactStreaming(true)
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

void SPUCopyThread::setCacheDir(const QString &cacheDir)
{
    _cacheDir = cacheDir;
}

void SPUCopyThread::setHttpHeaders(const QStringList &headers)
{
    _httpHeaders = headers;
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

    if (_isArtifactStreaming)
    {
        qDebug() << "  Artifact URL:" << _spuUrl;
        qDebug() << "  Target entry:" << _artifactEntry;
    }
    else if (_isUrlDownload)
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

    // Step 3: Copy SPU file (method depends on source type)
    bool copySuccess = false;

    if (_isArtifactStreaming)
    {
        emit preparationStatusUpdate(tr("Downloading artifact..."));
        copySuccess = downloadArtifactAndCopy(mountPoint);
    }
    else if (_isUrlDownload)
    {
        emit preparationStatusUpdate(tr("Streaming SPU file..."));
        copySuccess = streamUrlToFile(mountPoint);
    }
    else if (_isDirectFile)
    {
        emit preparationStatusUpdate(tr("Copying SPU file..."));
        copySuccess = copyDirectFile(mountPoint);
    }
    else
    {
        emit preparationStatusUpdate(tr("Extracting SPU file..."));
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

bool SPUCopyThread::streamUrlToFile(const QString &mountPoint)
{
    qDebug() << "SPUCopyThread: Streaming SPU from URL:" << _spuUrl;

    QString filename = _downloadFilename.isEmpty() ? _spuUrl.fileName() : _downloadFilename;
    if (filename.isEmpty())
    {
        filename = "downloaded.spu";
    }

    QString destPath = mountPoint + "/" + filename;
    qDebug() << "SPUCopyThread: Streaming to:" << destPath;

    // Open destination file on FAT32 mount
    QFile destFile(destPath);
    if (!destFile.open(QIODevice::WriteOnly))
    {
        emit error(tr("Failed to create file on USB drive: %1").arg(destFile.errorString()));
        return false;
    }

    // Optionally open cache file for simultaneous caching
    QFile cacheFile;
    bool caching = false;
    if (!_cacheDir.isEmpty())
    {
        QDir().mkpath(_cacheDir);
        QString cachePath = _cacheDir + "/" + filename;
        cacheFile.setFileName(cachePath);
        if (cacheFile.open(QIODevice::WriteOnly))
        {
            caching = true;
            qDebug() << "SPUCopyThread: Also caching to:" << cachePath;
        }
        else
        {
            qWarning() << "SPUCopyThread: Could not open cache file:" << cachePath;
        }
    }

    // Set up network request
    QNetworkAccessManager manager;
    QNetworkRequest request(_spuUrl);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    if (!_authToken.isEmpty())
    {
        request.setRawHeader("Authorization", QString("token %1").arg(_authToken).toUtf8());
        request.setRawHeader("Accept", "application/octet-stream");
    }

    for (const QString &header : _httpHeaders)
    {
        int colonPos = header.indexOf(':');
        if (colonPos > 0)
        {
            QByteArray name = header.left(colonPos).trimmed().toUtf8();
            QByteArray value = header.mid(colonPos + 1).trimmed().toUtf8();
            request.setRawHeader(name, value);
        }
    }

    QNetworkReply *reply = manager.get(request);

    bool success = true;
    qint64 totalWritten = 0;

    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);

    connect(reply, &QNetworkReply::downloadProgress, reply,
            [this](qint64 received, qint64 total) {
                if (total > 0)
                {
                    emit copyProgress(received, total);
                }
            });

    // Stream each chunk directly to FAT32 and cache
    connect(reply, &QNetworkReply::readyRead, reply,
            [this, &destFile, &cacheFile, &caching, &success, &totalWritten, reply]() {
                if (_cancelled || !success) return;

                QByteArray data = reply->readAll();
                qint64 written = destFile.write(data);
                if (written != data.size())
                {
                    success = false;
                    return;
                }
                totalWritten += written;

                if (caching)
                {
                    cacheFile.write(data);
                }
            });

    loop.exec();

    // Write any remaining data
    if (success && !_cancelled)
    {
        QByteArray remaining = reply->readAll();
        if (!remaining.isEmpty())
        {
            qint64 written = destFile.write(remaining);
            if (written != remaining.size()) success = false;
            totalWritten += written;
            if (caching) cacheFile.write(remaining);
        }
    }

    destFile.flush();
    destFile.close();
    if (caching)
    {
        cacheFile.flush();
        cacheFile.close();
    }

    if (reply->error() != QNetworkReply::NoError)
    {
        emit error(tr("Download failed: %1").arg(reply->errorString()));
        destFile.remove();
        if (caching) cacheFile.remove();
        reply->deleteLater();
        return false;
    }

    if (!success)
    {
        emit error(tr("Error writing to USB drive: %1").arg(destFile.errorString()));
        destFile.remove();
        if (caching) cacheFile.remove();
        reply->deleteLater();
        return false;
    }

    reply->deleteLater();
    qDebug() << "SPUCopyThread: Streaming complete," << totalWritten << "bytes written";
    return true;
}

bool SPUCopyThread::downloadArtifactAndCopy(const QString &mountPoint)
{
    qDebug() << "SPUCopyThread: Downloading artifact ZIP from:" << _spuUrl;
    qDebug() << "SPUCopyThread: Target SPU entry:" << _artifactEntry;

    // Determine cache path for the ZIP
    QString cachePath;
    if (!_cacheDir.isEmpty())
    {
        QDir().mkpath(_cacheDir);
        // Use URL hash as cache key
        QString urlHash = QString::number(qHash(_spuUrl.toString()), 16);
        cachePath = _cacheDir + "/artifact_" + urlHash + ".zip";

        // Check if already cached
        if (QFile::exists(cachePath))
        {
            qDebug() << "SPUCopyThread: Using cached artifact ZIP:" << cachePath;
            _archivePath = cachePath;
            _spuEntry = _artifactEntry;
            return extractAndCopy(mountPoint);
        }
    }
    else
    {
        // No cache dir - use temp location
        QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
        cachePath = tempDir + "/laerdal-artifact-" + _spuUrl.fileName();
    }

    qDebug() << "SPUCopyThread: Downloading artifact to:" << cachePath;

    // Download the full artifact ZIP
    QNetworkAccessManager manager;
    QNetworkRequest request(_spuUrl);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    if (!_authToken.isEmpty())
    {
        request.setRawHeader("Authorization", QString("Bearer %1").arg(_authToken).toUtf8());
        request.setRawHeader("Accept", "application/octet-stream");
    }

    for (const QString &header : _httpHeaders)
    {
        int colonPos = header.indexOf(':');
        if (colonPos > 0)
        {
            QByteArray name = header.left(colonPos).trimmed().toUtf8();
            QByteArray value = header.mid(colonPos + 1).trimmed().toUtf8();
            request.setRawHeader(name, value);
        }
    }

    QNetworkReply *reply = manager.get(request);

    QFile file(cachePath);
    if (!file.open(QIODevice::WriteOnly))
    {
        emit error(tr("Failed to create cache file: %1").arg(file.errorString()));
        reply->deleteLater();
        return false;
    }

    QEventLoop loop;
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);

    connect(reply, &QNetworkReply::downloadProgress, reply,
            [this](qint64 received, qint64 total) {
                if (total > 0)
                {
                    // Show download progress as first half of the operation
                    emit copyProgress(received, total * 2);
                }
            });

    connect(reply, &QNetworkReply::readyRead, reply,
            [&file, reply]() {
                file.write(reply->readAll());
            });

    loop.exec();

    QByteArray remaining = reply->readAll();
    if (!remaining.isEmpty())
    {
        file.write(remaining);
    }
    file.close();

    if (reply->error() != QNetworkReply::NoError)
    {
        emit error(tr("Artifact download failed: %1").arg(reply->errorString()));
        file.remove();
        reply->deleteLater();
        return false;
    }

    reply->deleteLater();
    qDebug() << "SPUCopyThread: Artifact download complete, size:" << QFileInfo(cachePath).size();

    // Now extract the SPU entry from the downloaded ZIP
    _archivePath = cachePath;
    _spuEntry = _artifactEntry;
    return extractAndCopy(mountPoint);
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
