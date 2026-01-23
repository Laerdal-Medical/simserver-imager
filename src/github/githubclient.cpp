/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "githubclient.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDir>
#include <QSettings>
#include <archive.h>
#include <archive_entry.h>

GitHubClient::GitHubClient(QObject *parent)
    : QObject(parent)
{
    loadPartialArtifactDownload();
}

GitHubClient::~GitHubClient()
{
    // Cancel any pending requests
    for (auto reply : _pendingRequests.keys()) {
        reply->abort();
        reply->deleteLater();
    }
    _pendingRequests.clear();

    // Cancel active inspection reply
    if (_activeInspectionReply) {
        _activeInspectionReply->abort();
        _activeInspectionReply->deleteLater();
        _activeInspectionReply = nullptr;
    }

    // Clean up file handle
    if (_activeInspectionFile) {
        _activeInspectionFile->close();
        delete _activeInspectionFile;
        _activeInspectionFile = nullptr;
    }
}

void GitHubClient::cancelArtifactInspection(bool preserveForResume)
{
    if (_activeInspectionReply) {
        qDebug() << "GitHubClient: Cancelling artifact inspection download, preserveForResume:" << preserveForResume;

        // Close and clean up the file handle
        if (_activeInspectionFile) {
            _activeInspectionFile->flush();
            _activeInspectionFile->close();
            delete _activeInspectionFile;
            _activeInspectionFile = nullptr;
        }

        if (preserveForResume && _activeInspectionBytesWritten > 0) {
            // Save partial download state for resume
            _partialArtifactDownload.bytesDownloaded = _activeInspectionBytesWritten;
            _partialArtifactDownload.isValid = true;
            savePartialArtifactDownload();
            qDebug() << "GitHubClient: Preserved partial artifact download:"
                     << _activeInspectionBytesWritten << "bytes";
        } else {
            // Delete the partial file
            if (!_activeInspectionPartialPath.isEmpty() && QFile::exists(_activeInspectionPartialPath)) {
                qDebug() << "GitHubClient: Deleting partial cache file:" << _activeInspectionPartialPath;
                QFile::remove(_activeInspectionPartialPath);
            }
            clearPartialArtifactDownload();
        }

        _activeInspectionZipPath.clear();
        _activeInspectionPartialPath.clear();
        _activeInspectionBytesWritten = 0;

        // Just abort - the finished handler will clean up the reply
        // and check for OperationCanceledError
        _activeInspectionReply->abort();
        // Don't deleteLater here - the finished signal handler does that
        // Don't set to nullptr here - the finished handler does that
        emit artifactInspectionCancelled();
    }
}

void GitHubClient::setAuthToken(const QString &token)
{
    _authToken = token;
}

void GitHubClient::fetchReleases(const QString &owner, const QString &repo)
{
    QString urlStr = QString("%1/repos/%2/%3/releases")
                         .arg(API_BASE_URL, owner, repo);

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestReleases;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });

    qDebug() << "GitHubClient: Fetching releases for" << owner << "/" << repo;
}

void GitHubClient::fetchBranchFile(const QString &owner, const QString &repo,
                                    const QString &branch, const QString &path)
{
    // Use raw.githubusercontent.com for direct file access
    QString urlStr = QString("%1/%2/%3/%4/%5")
                         .arg(RAW_BASE_URL, owner, repo, branch, path);

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestFile;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply, path]() {
        reply->deleteLater();
        _pendingRequests.remove(reply);
        _requestMetadata.remove(reply);

        if (reply->error() != QNetworkReply::NoError) {
            emit error(tr("Failed to fetch file: %1").arg(reply->errorString()));
            return;
        }

        checkRateLimitHeaders(reply);

        // For raw file downloads, the URL is the download URL
        QString downloadUrl = reply->url().toString();
        QString fileName = path.split('/').last();

        emit fileUrlReady(downloadUrl, fileName);
    });

    qDebug() << "GitHubClient: Fetching file" << path << "from branch" << branch;
}

void GitHubClient::fetchTagFile(const QString &owner, const QString &repo,
                                 const QString &tag, const QString &path)
{
    // Tags work the same as branches for raw file access
    fetchBranchFile(owner, repo, tag, path);
}

void GitHubClient::fetchRepoInfo(const QString &owner, const QString &repo)
{
    QString urlStr = QString("%1/repos/%2/%3")
                         .arg(API_BASE_URL, owner, repo);

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestRepoInfo;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });

    qDebug() << "GitHubClient: Fetching repo info for" << owner << "/" << repo;
}

void GitHubClient::fetchBranches(const QString &owner, const QString &repo)
{
    // Use per_page=100 to get more branches (GitHub default is 30)
    // This helps avoid missing branches like 'main' when repos have many branches
    QString urlStr = QString("%1/repos/%2/%3/branches?per_page=100")
                         .arg(API_BASE_URL, owner, repo);

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestBranches;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });

    qDebug() << "GitHubClient: Fetching branches for" << owner << "/" << repo;
}

void GitHubClient::fetchTags(const QString &owner, const QString &repo)
{
    // Use per_page=100 to get more tags (GitHub default is 30)
    QString urlStr = QString("%1/repos/%2/%3/tags?per_page=100")
                         .arg(API_BASE_URL, owner, repo);

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestTags;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });

    qDebug() << "GitHubClient: Fetching tags for" << owner << "/" << repo;
}

void GitHubClient::searchWicFilesInReleases(const QString &owner, const QString &repo)
{
    QString urlStr = QString("%1/repos/%2/%3/releases")
                         .arg(API_BASE_URL, owner, repo);

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestWicSearch;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });

    qDebug() << "GitHubClient: Searching WIC files in" << owner << "/" << repo;
}

QString GitHubClient::getAssetDownloadUrl(const QString &owner, const QString &repo, qint64 assetId)
{
    // For private repos, we need to use the API endpoint with authentication
    // For public repos, the browser_download_url works directly
    QString urlStr = QString("%1/repos/%2/%3/releases/assets/%4")
                         .arg(API_BASE_URL, owner, repo, QString::number(assetId));

    return urlStr;
}

void GitHubClient::fetchWorkflowRuns(const QString &owner, const QString &repo,
                                      const QString &branch, const QString &status)
{
    QString urlStr = QString("%1/repos/%2/%3/actions/runs?per_page=20")
                         .arg(API_BASE_URL, owner, repo);

    if (!branch.isEmpty()) {
        urlStr += QString("&branch=%1").arg(branch);
    }
    if (!status.isEmpty()) {
        urlStr += QString("&status=%1").arg(status);
    }

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestWorkflowRuns;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });

    qDebug() << "GitHubClient: Fetching workflow runs for" << owner << "/" << repo;
}

void GitHubClient::fetchWorkflowArtifacts(const QString &owner, const QString &repo, qint64 runId)
{
    QString urlStr = QString("%1/repos/%2/%3/actions/runs/%4/artifacts")
                         .arg(API_BASE_URL, owner, repo, QString::number(runId));

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestWorkflowArtifacts;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });

    qDebug() << "GitHubClient: Fetching artifacts for run" << runId;
}

void GitHubClient::searchWicFilesInArtifacts(const QString &owner, const QString &repo,
                                              const QString &branch)
{
    // First fetch workflow runs, then we'll get artifacts from successful runs
    // Use per_page=30 to get more workflow runs (some may not have WIC artifacts)
    QString urlStr = QString("%1/repos/%2/%3/actions/runs?per_page=30&status=success")
                         .arg(API_BASE_URL, owner, repo);

    if (!branch.isEmpty()) {
        urlStr += QString("&branch=%1").arg(branch);
    }

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestArtifactWicSearch;
    _requestMetadata[reply] = qMakePair(owner, repo);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });

    qDebug() << "GitHubClient: Searching WIC artifacts in" << owner << "/" << repo;
}

QString GitHubClient::getArtifactDownloadUrl(const QString &owner, const QString &repo, qint64 artifactId)
{
    // Artifact download requires authentication
    QString urlStr = QString("%1/repos/%2/%3/actions/artifacts/%4/zip")
                         .arg(API_BASE_URL, owner, repo, QString::number(artifactId));

    return urlStr;
}

void GitHubClient::downloadArtifact(const QString &owner, const QString &repo,
                                     qint64 artifactId, const QString &destinationPath)
{
    QString urlStr = getArtifactDownloadUrl(owner, repo, artifactId);
    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));

    // Don't auto-follow redirects - we need to manually handle them to add auth headers
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::ManualRedirectPolicy);

    QNetworkReply *reply = _networkManager.get(request);
    _activeInspectionReply = reply;

    qDebug() << "GitHubClient: Starting artifact download from" << urlStr << "to" << destinationPath;

    connect(reply, &QNetworkReply::finished, this, [this, reply, destinationPath]() {
        _activeInspectionReply = nullptr;
        reply->deleteLater();

        // Check for redirect (302)
        int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (statusCode == 302 || statusCode == 301 || statusCode == 307 || statusCode == 308) {
            QUrl redirectUrl = reply->header(QNetworkRequest::LocationHeader).toUrl();
            if (redirectUrl.isValid()) {
                qDebug() << "GitHubClient: Following redirect to" << redirectUrl.toString();
                downloadArtifactFromUrl(redirectUrl, destinationPath);
                return;
            }
        }

        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "GitHubClient: Artifact download failed:" << reply->errorString();
            emit error(tr("Failed to download artifact: %1").arg(reply->errorString()));
            return;
        }

        // Save the downloaded data to the destination file
        QFile file(destinationPath);
        if (!file.open(QIODevice::WriteOnly)) {
            qWarning() << "GitHubClient: Failed to open destination file:" << destinationPath;
            emit error(tr("Failed to save artifact: %1").arg(file.errorString()));
            return;
        }

        QByteArray data = reply->readAll();
        file.write(data);
        file.close();

        qDebug() << "GitHubClient: Artifact downloaded successfully to" << destinationPath
                 << "size:" << data.size();

        emit artifactDownloadComplete(destinationPath);
    });
}

void GitHubClient::downloadArtifactFromUrl(const QUrl &url, const QString &destinationPath)
{
    // Check if this is a GitHub URL or an external URL (like Azure blob storage)
    // External URLs (like Azure) use SAS tokens in the query string and don't need/want our GitHub auth header
    bool isGitHubUrl = url.host().endsWith("github.com") || url.host().endsWith("githubusercontent.com");

    QNetworkRequest request;
    if (isGitHubUrl) {
        request = createAuthenticatedRequest(url);
    } else {
        // External URL (Azure blob, etc) - don't add auth header, the URL has its own auth
        request.setUrl(url);
        request.setHeader(QNetworkRequest::UserAgentHeader, "Laerdal-SimServer-Imager/1.0");
    }
    // No timeout for downloads - they can take a long time for large files
    request.setTransferTimeout(0);

    // Allow redirects from here (the blob storage URL shouldn't redirect further)
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply *reply = _networkManager.get(request);

    qDebug() << "GitHubClient: Downloading artifact from redirect URL (isGitHubUrl:" << isGitHubUrl << ")";

    connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 bytesReceived, qint64 bytesTotal) {
        emit artifactDownloadProgress(bytesReceived, bytesTotal);
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, destinationPath]() {
        reply->deleteLater();

        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "GitHubClient: Artifact download from redirect failed:" << reply->errorString();
            emit error(tr("Failed to download artifact: %1").arg(reply->errorString()));
            return;
        }

        // Save the downloaded data to the destination file
        QFile file(destinationPath);
        if (!file.open(QIODevice::WriteOnly)) {
            qWarning() << "GitHubClient: Failed to open destination file:" << destinationPath;
            emit error(tr("Failed to save artifact: %1").arg(file.errorString()));
            return;
        }

        QByteArray data = reply->readAll();
        file.write(data);
        file.close();

        qDebug() << "GitHubClient: Artifact downloaded successfully to" << destinationPath
                 << "size:" << data.size();

        emit artifactDownloadComplete(destinationPath);
    });
}

void GitHubClient::inspectArtifactContents(const QString &owner, const QString &repo,
                                            qint64 artifactId, const QString &artifactName,
                                            const QString &branch)
{
    qDebug() << "GitHubClient: Inspecting artifact contents for" << artifactName << "id:" << artifactId;

    // Create cache directory for artifact download (persistent across sessions)
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QString artifactCacheDir = cacheDir + "/artifacts";
    QDir().mkpath(artifactCacheDir);
    QString zipPath = artifactCacheDir + QString("/artifact_%1.zip").arg(artifactId);

    // Check if artifact is already cached and valid
    if (QFile::exists(zipPath)) {
        qDebug() << "GitHubClient: Checking cached artifact:" << zipPath;
        QJsonArray imageFiles = listImageFilesInZip(zipPath);
        if (!imageFiles.isEmpty()) {
            qDebug() << "GitHubClient: Using valid cached artifact:" << zipPath;
            emit artifactContentsReady(artifactId, artifactName, owner, repo, branch, imageFiles, zipPath);
            return;
        } else {
            // Cached file is invalid or corrupt - delete it and re-download
            qDebug() << "GitHubClient: Cached artifact is invalid, deleting:" << zipPath;
            QFile::remove(zipPath);
        }
    }

    // Download the artifact - initial request gets a 302 redirect from GitHub API
    QString urlStr = getArtifactDownloadUrl(owner, repo, artifactId);
    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));

    // Don't auto-follow redirects - we need to manually handle them to add auth headers
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::ManualRedirectPolicy);

    QNetworkReply *reply = _networkManager.get(request);
    _activeInspectionReply = reply;

    connect(reply, &QNetworkReply::finished, this, [this, reply, owner, repo, artifactId, artifactName, branch, zipPath]() {
        _activeInspectionReply = nullptr;
        reply->deleteLater();

        // Check for redirect (302)
        int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (statusCode == 302 || statusCode == 301 || statusCode == 307 || statusCode == 308) {
            QUrl redirectUrl = reply->header(QNetworkRequest::LocationHeader).toUrl();
            if (redirectUrl.isValid()) {
                qDebug() << "GitHubClient: Following redirect for artifact inspection";
                inspectArtifactFromUrl(redirectUrl, owner, repo, artifactId, artifactName, branch, zipPath);
                return;
            }
        }

        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "GitHubClient: Artifact inspection download failed:" << reply->errorString();
            emit error(tr("Failed to inspect artifact: %1").arg(reply->errorString()));
            return;
        }

        // Save and inspect
        QFile file(zipPath);
        if (!file.open(QIODevice::WriteOnly)) {
            emit error(tr("Failed to save artifact for inspection: %1").arg(file.errorString()));
            return;
        }

        QByteArray data = reply->readAll();
        file.write(data);
        file.close();

        qDebug() << "GitHubClient: Artifact cached to:" << zipPath;

        // Now scan the ZIP for all image files (WIC + SPU)
        QJsonArray imageFiles = listImageFilesInZip(zipPath);
        emit artifactContentsReady(artifactId, artifactName, owner, repo, branch, imageFiles, zipPath);
    });
}

void GitHubClient::inspectArtifactFromUrl(const QUrl &url, const QString &owner, const QString &repo,
                                           qint64 artifactId, const QString &artifactName,
                                           const QString &branch, const QString &zipPath)
{
    QString partialPath = zipPath + ".partial";

    // Check if we're resuming a partial download
    qint64 startOffset = 0;
    if (_partialArtifactDownload.isValid &&
        _partialArtifactDownload.artifactId == artifactId &&
        QFile::exists(_partialArtifactDownload.partialPath)) {
        startOffset = _partialArtifactDownload.bytesDownloaded;
        partialPath = _partialArtifactDownload.partialPath;
        qDebug() << "GitHubClient: Resuming artifact download from offset:" << startOffset;
    }

    // Check if this is a GitHub URL or an external URL
    bool isGitHubUrl = url.host().endsWith("github.com") || url.host().endsWith("githubusercontent.com");

    QNetworkRequest request;
    if (isGitHubUrl) {
        request = createAuthenticatedRequest(url);
    } else {
        request.setUrl(url);
        request.setHeader(QNetworkRequest::UserAgentHeader, "Laerdal-SimServer-Imager/1.0");
    }
    // No timeout for downloads - they can take a long time for large files
    request.setTransferTimeout(0);

    // Add Range header for resume support
    if (startOffset > 0) {
        request.setRawHeader("Range", QString("bytes=%1-").arg(startOffset).toUtf8());
    }

    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    // Store metadata for partial download tracking
    _partialArtifactDownload.partialPath = partialPath;
    _partialArtifactDownload.finalPath = zipPath;
    _partialArtifactDownload.owner = owner;
    _partialArtifactDownload.repo = repo;
    _partialArtifactDownload.branch = branch;
    _partialArtifactDownload.artifactName = artifactName;
    _partialArtifactDownload.artifactId = artifactId;
    _partialArtifactDownload.downloadUrl = url;

    // Open the file for writing (append if resuming)
    _activeInspectionFile = new QFile(partialPath);
    QIODevice::OpenMode mode = startOffset > 0 ? (QIODevice::WriteOnly | QIODevice::Append)
                                                : QIODevice::WriteOnly;
    if (!_activeInspectionFile->open(mode)) {
        emit error(tr("Failed to open file for writing: %1").arg(_activeInspectionFile->errorString()));
        delete _activeInspectionFile;
        _activeInspectionFile = nullptr;
        return;
    }
    _activeInspectionBytesWritten = startOffset;

    QNetworkReply *reply = _networkManager.get(request);
    _activeInspectionReply = reply;
    _activeInspectionZipPath = zipPath;
    _activeInspectionPartialPath = partialPath;

    // Write data incrementally as it arrives
    connect(reply, &QNetworkReply::readyRead, this, [this, reply]() {
        if (this->_activeInspectionFile && this->_activeInspectionFile->isOpen()) {
            QByteArray data = reply->readAll();
            qint64 written = this->_activeInspectionFile->write(data);
            if (written > 0) {
                this->_activeInspectionBytesWritten += written;
            }
        }
    });

    connect(reply, &QNetworkReply::downloadProgress, this, [this, startOffset](qint64 bytesReceived, qint64 bytesTotal) {
        // Adjust for resume offset
        qint64 totalReceived = startOffset + bytesReceived;
        qint64 totalSize = (bytesTotal > 0) ? (startOffset + bytesTotal) : 0;

        // Store total size for partial download info
        if (totalSize > 0) {
            _partialArtifactDownload.totalSize = totalSize;
        }

        emit artifactDownloadProgress(totalReceived, totalSize);
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, owner, repo, artifactId, artifactName, branch, zipPath, partialPath]() {
        this->_activeInspectionReply = nullptr;
        this->_activeInspectionZipPath.clear();
        this->_activeInspectionPartialPath.clear();

        // Close and clean up the file
        if (this->_activeInspectionFile) {
            this->_activeInspectionFile->flush();
            this->_activeInspectionFile->close();
            delete this->_activeInspectionFile;
            this->_activeInspectionFile = nullptr;
        }

        reply->deleteLater();

        // Check if cancelled (OperationCanceledError)
        if (reply->error() == QNetworkReply::OperationCanceledError) {
            qDebug() << "GitHubClient: Artifact inspection cancelled by user";
            return;
        }

        if (reply->error() != QNetworkReply::NoError) {
            emit error(tr("Failed to download artifact for inspection: %1").arg(reply->errorString()));
            // Clean up partial file on error
            QFile::remove(partialPath);
            clearPartialArtifactDownload();
            return;
        }

        // Rename partial file to final path
        if (QFile::exists(zipPath)) {
            QFile::remove(zipPath);
        }
        if (!QFile::rename(partialPath, zipPath)) {
            emit error(tr("Failed to finalize artifact download"));
            return;
        }

        qDebug() << "GitHubClient: Artifact downloaded for inspection, size:" << _activeInspectionBytesWritten;
        _activeInspectionBytesWritten = 0;

        // Clear partial download state since we completed successfully
        clearPartialArtifactDownload();

        // Scan the ZIP for all image files (WIC + SPU)
        QJsonArray imageFiles = listImageFilesInZip(zipPath);
        emit artifactContentsReady(artifactId, artifactName, owner, repo, branch, imageFiles, zipPath);
    });
}

QJsonArray GitHubClient::listWicFilesInZip(const QString &zipPath)
{
    qDebug() << "GitHubClient: Listing WIC files in ZIP:" << zipPath;
    QJsonArray wicFiles;

    struct archive *a = archive_read_new();
    struct archive_entry *entry;

    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (archive_read_open_filename(a, zipPath.toUtf8().constData(), 10240) != ARCHIVE_OK) {
        qWarning() << "GitHubClient: Failed to open ZIP for listing:" << archive_error_string(a);
        archive_read_free(a);
        return wicFiles;
    }

    // WIC file extensions only
    QStringList wicExtensions = {".wic", ".wic.gz", ".wic.xz", ".wic.zst", ".wic.bz2"};

    while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
        QString entryName = QString::fromUtf8(archive_entry_pathname(entry));
        qint64 entrySize = archive_entry_size(entry);

        // Check if this is a WIC file
        for (const QString &ext : wicExtensions) {
            if (entryName.endsWith(ext, Qt::CaseInsensitive)) {
                QJsonObject wicFile;
                wicFile["filename"] = entryName;
                wicFile["size"] = entrySize;

                // Extract a display name from the filename
                QString displayName = QFileInfo(entryName).fileName();
                wicFile["display_name"] = displayName;

                wicFiles.append(wicFile);
                qDebug() << "GitHubClient: Found WIC file in ZIP:" << entryName << "size:" << entrySize;
                break;
            }
        }
        archive_read_data_skip(a);
    }

    archive_read_close(a);
    archive_read_free(a);

    qDebug() << "GitHubClient: Found" << wicFiles.size() << "WIC files in ZIP";
    return wicFiles;
}

QJsonArray GitHubClient::listSpuFilesInZip(const QString &zipPath)
{
    qDebug() << "GitHubClient: Listing SPU files in ZIP:" << zipPath;
    QJsonArray spuFiles;

    struct archive *a = archive_read_new();
    struct archive_entry *entry;

    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (archive_read_open_filename(a, zipPath.toUtf8().constData(), 10240) != ARCHIVE_OK) {
        qWarning() << "GitHubClient: Failed to open ZIP for SPU listing:" << archive_error_string(a);
        archive_read_free(a);
        return spuFiles;
    }

    while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
        QString entryName = QString::fromUtf8(archive_entry_pathname(entry));
        qint64 entrySize = archive_entry_size(entry);

        // Check if this is an SPU file
        if (entryName.endsWith(".spu", Qt::CaseInsensitive)) {
            QJsonObject spuFile;
            spuFile["filename"] = entryName;
            spuFile["size"] = entrySize;

            // Extract a display name from the filename
            QString displayName = QFileInfo(entryName).fileName();
            spuFile["display_name"] = displayName;

            spuFiles.append(spuFile);
            qDebug() << "GitHubClient: Found SPU file in ZIP:" << entryName << "size:" << entrySize;
        }
        archive_read_data_skip(a);
    }

    archive_read_close(a);
    archive_read_free(a);

    qDebug() << "GitHubClient: Found" << spuFiles.size() << "SPU files in ZIP";
    return spuFiles;
}

QJsonArray GitHubClient::listImageFilesInZip(const QString &zipPath)
{
    qDebug() << "GitHubClient: Listing all image files (WIC + SPU) in ZIP:" << zipPath;
    QJsonArray imageFiles;

    struct archive *a = archive_read_new();
    struct archive_entry *entry;

    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (archive_read_open_filename(a, zipPath.toUtf8().constData(), 10240) != ARCHIVE_OK) {
        qWarning() << "GitHubClient: Failed to open ZIP for listing:" << archive_error_string(a);
        archive_read_free(a);
        return imageFiles;
    }

    // Image file extensions to look for
    QStringList wicExtensions = {".wic", ".wic.gz", ".wic.xz", ".wic.zst", ".wic.bz2"};

    while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
        QString entryName = QString::fromUtf8(archive_entry_pathname(entry));
        qint64 entrySize = archive_entry_size(entry);
        QString displayName = QFileInfo(entryName).fileName();

        // Determine the image type from extension
        QString type;
        if (entryName.endsWith(".spu", Qt::CaseInsensitive)) {
            type = "spu";
        } else if (entryName.endsWith(".vsi", Qt::CaseInsensitive)) {
            type = "vsi";
        } else {
            for (const QString &ext : wicExtensions) {
                if (entryName.endsWith(ext, Qt::CaseInsensitive)) {
                    type = "wic";
                    break;
                }
            }
        }

        if (!type.isEmpty()) {
            QJsonObject imageFile;
            imageFile["filename"] = entryName;
            imageFile["size"] = entrySize;
            imageFile["display_name"] = displayName;
            imageFile["type"] = type;
            imageFiles.append(imageFile);
            qDebug() << "GitHubClient: Found" << type.toUpper() << "file:" << entryName;
        }

        archive_read_data_skip(a);
    }

    archive_read_close(a);
    archive_read_free(a);

    qDebug() << "GitHubClient: Found" << imageFiles.size() << "image files in ZIP";
    return imageFiles;
}

void GitHubClient::inspectArtifactSpuContents(const QString &owner, const QString &repo,
                                               qint64 artifactId, const QString &artifactName,
                                               const QString &branch)
{
    qDebug() << "GitHubClient: Inspecting artifact for SPU contents:" << artifactName;

    // Get the download URL
    QString downloadUrl = getArtifactDownloadUrl(owner, repo, artifactId);

    // Determine cache path for this artifact
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QString artifactCacheDir = cacheDir + "/github-artifacts";
    QDir().mkpath(artifactCacheDir);
    QString zipPath = artifactCacheDir + QString("/artifact_%1.zip").arg(artifactId);

    // Check if artifact is already cached and valid
    if (QFile::exists(zipPath)) {
        qDebug() << "GitHubClient: Checking cached artifact for SPU:" << zipPath;
        QJsonArray spuFiles = listSpuFilesInZip(zipPath);
        if (!spuFiles.isEmpty()) {
            qDebug() << "GitHubClient: Using valid cached artifact for SPU:" << zipPath;
            emit artifactSpuContentsReady(artifactId, artifactName, owner, repo, branch, spuFiles, zipPath);
            return;
        } else {
            qDebug() << "GitHubClient: Cached artifact has no SPU files or is invalid, re-downloading";
            QFile::remove(zipPath);
        }
    }

    // Download and inspect
    inspectArtifactSpuFromUrl(QUrl(downloadUrl), owner, repo, artifactId, artifactName, branch, zipPath);
}

void GitHubClient::inspectArtifactSpuFromUrl(const QUrl &url, const QString &owner, const QString &repo,
                                              qint64 artifactId, const QString &artifactName,
                                              const QString &branch, const QString &zipPath)
{
    qDebug() << "GitHubClient: Downloading artifact for SPU inspection:" << url.toString();

    // Check if this is a GitHub URL or an external URL
    bool isGitHubUrl = url.host().endsWith("github.com") || url.host().endsWith("githubusercontent.com");

    QNetworkRequest request;
    if (isGitHubUrl) {
        request = createAuthenticatedRequest(url);
    } else {
        request.setUrl(url);
        request.setHeader(QNetworkRequest::UserAgentHeader, "Laerdal-SimServer-Imager/1.0");
    }
    // No timeout for downloads - they can take a long time for large files
    request.setTransferTimeout(0);

    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply *reply = _networkManager.get(request);
    _activeInspectionReply = reply;
    _activeInspectionZipPath = zipPath;

    connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 bytesReceived, qint64 bytesTotal) {
        emit artifactDownloadProgress(bytesReceived, bytesTotal);
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, owner, repo, artifactId, artifactName, branch, zipPath]() {
        _activeInspectionReply = nullptr;
        _activeInspectionZipPath.clear();
        reply->deleteLater();

        // Check if cancelled (OperationCanceledError)
        if (reply->error() == QNetworkReply::OperationCanceledError) {
            qDebug() << "GitHubClient: SPU artifact inspection cancelled by user";
            return;
        }

        if (reply->error() != QNetworkReply::NoError) {
            emit error(tr("Failed to download artifact for SPU inspection: %1").arg(reply->errorString()));
            return;
        }

        QFile file(zipPath);
        if (!file.open(QIODevice::WriteOnly)) {
            emit error(tr("Failed to save artifact for SPU inspection: %1").arg(file.errorString()));
            return;
        }

        QByteArray data = reply->readAll();
        file.write(data);
        file.close();

        qDebug() << "GitHubClient: Artifact downloaded for SPU inspection, size:" << data.size();

        // Scan the ZIP for SPU files
        QJsonArray spuFiles = listSpuFilesInZip(zipPath);
        emit artifactSpuContentsReady(artifactId, artifactName, owner, repo, branch, spuFiles, zipPath);
    });
}

void GitHubClient::checkRateLimit()
{
    QString urlStr = QString("%1/rate_limit").arg(API_BASE_URL);

    QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
    QNetworkReply *reply = _networkManager.get(request);

    _pendingRequests[reply] = RequestRateLimit;

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleNetworkReply(reply);
    });
}

void GitHubClient::handleNetworkReply(QNetworkReply *reply)
{
    reply->deleteLater();

    RequestType requestType = _pendingRequests.take(reply);
    QPair<QString, QString> metadata = _requestMetadata.take(reply);

    // Check for rate limiting
    checkRateLimitHeaders(reply);

    if (reply->error() != QNetworkReply::NoError) {
        int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        if (statusCode == 403) {
            // Might be rate limited
            QString rateLimitRemaining = reply->rawHeader("X-RateLimit-Remaining");
            if (rateLimitRemaining == "0") {
                qint64 resetTime = reply->rawHeader("X-RateLimit-Reset").toLongLong();
                emit rateLimitExceeded(resetTime);
                return;
            }
        }

        if (statusCode == 404) {
            emit error(tr("Repository not found or not accessible: %1/%2")
                           .arg(metadata.first, metadata.second));
        } else {
            emit error(tr("GitHub API error: %1").arg(reply->errorString()));
        }
        return;
    }

    QByteArray responseData = reply->readAll();
    QJsonDocument doc = QJsonDocument::fromJson(responseData);

    if (doc.isNull()) {
        emit error(tr("Invalid JSON response from GitHub"));
        return;
    }

    switch (requestType) {
    case RequestReleases: {
        if (doc.isArray()) {
            emit releasesReady(doc.array());
        } else {
            emit error(tr("Unexpected response format for releases"));
        }
        break;
    }

    case RequestRepoInfo: {
        if (doc.isObject()) {
            QJsonObject repoObj = doc.object();
            QString defaultBranch = repoObj["default_branch"].toString();
            emit repoInfoReady(metadata.first, metadata.second, defaultBranch);
            qDebug() << "GitHubClient: Repo" << metadata.first << "/" << metadata.second
                     << "default branch:" << defaultBranch;
        } else {
            emit error(tr("Unexpected response format for repository info"));
        }
        break;
    }

    case RequestBranches: {
        if (doc.isArray()) {
            QJsonArray branches;
            for (const auto &item : doc.array()) {
                QJsonObject branch = item.toObject();
                branches.append(branch["name"].toString());
            }
            emit branchesReady(branches);
        }
        break;
    }

    case RequestTags: {
        if (doc.isArray()) {
            QJsonArray tags;
            for (const auto &item : doc.array()) {
                QJsonObject tag = item.toObject();
                tags.append(tag["name"].toString());
            }
            emit tagsReady(tags);
        }
        break;
    }

    case RequestWicSearch: {
        if (doc.isArray()) {
            QJsonArray wicFiles = filterWicAssets(doc.array(), metadata.first, metadata.second);
            emit wicFilesReady(wicFiles);
        }
        break;
    }

    case RequestRateLimit: {
        if (doc.isObject()) {
            QJsonObject rate = doc.object()["rate"].toObject();
            int remaining = rate["remaining"].toInt();
            int limit = rate["limit"].toInt();
            qint64 reset = rate["reset"].toVariant().toLongLong();
            emit rateLimitInfo(remaining, limit, reset);
        }
        break;
    }

    case RequestFile:
        // File requests are handled inline in fetchBranchFile/fetchTagFile
        break;

    case RequestWorkflowRuns: {
        if (doc.isObject()) {
            QJsonArray runs = doc.object()["workflow_runs"].toArray();
            emit workflowRunsReady(runs);
        }
        break;
    }

    case RequestWorkflowArtifacts: {
        if (doc.isObject()) {
            QJsonArray artifacts = doc.object()["artifacts"].toArray();

            // Check if this is part of an artifact WIC search
            RunInfo runInfo = _artifactRunInfo.take(reply);
            if (!runInfo.owner.isEmpty()) {
                QString key = QString("%1/%2").arg(runInfo.owner, runInfo.repo);
                if (_artifactSearchStates.contains(key)) {
                    ArtifactSearchState &state = _artifactSearchStates[key];

                    // Filter and collect WIC artifacts from this run
                    QJsonArray wicArtifacts = filterWicArtifacts(artifacts, runInfo.owner,
                                                                  runInfo.repo, runInfo.branch,
                                                                  runInfo.createdAt);
                    for (const auto &artifact : wicArtifacts) {
                        state.collectedArtifacts.append(artifact);
                    }

                    state.pendingRuns--;
                    qDebug() << "GitHubClient: Artifact fetch complete for run" << runInfo.runId
                             << ", pending:" << state.pendingRuns
                             << ", collected:" << state.collectedArtifacts.size();

                    // If all runs are done, emit the collected artifacts
                    if (state.pendingRuns <= 0) {
                        QJsonArray finalArtifacts = state.collectedArtifacts;
                        _artifactSearchStates.remove(key);
                        emit artifactWicFilesReady(finalArtifacts);
                    }
                    break;
                }
            }

            // Regular artifact fetch (not part of WIC search)
            emit workflowArtifactsReady(artifacts);
        }
        break;
    }

    case RequestArtifactWicSearch: {
        if (doc.isObject()) {
            QJsonArray runs = doc.object()["workflow_runs"].toArray();
            QString owner = metadata.first;
            QString repo = metadata.second;
            QString key = QString("%1/%2").arg(owner, repo);

            if (runs.isEmpty()) {
                // No runs found, emit empty result
                qDebug() << "GitHubClient: No workflow runs found for" << key;
                emit artifactWicFilesReady(QJsonArray());
                break;
            }

            // Initialize search state
            ArtifactSearchState state;
            state.owner = owner;
            state.repo = repo;
            state.pendingRuns = runs.size();
            _artifactSearchStates[key] = state;

            qDebug() << "GitHubClient: Found" << runs.size() << "workflow runs for" << key
                     << ", fetching artifacts...";

            // Fetch artifacts for each run
            for (const auto &runValue : runs) {
                QJsonObject run = runValue.toObject();
                qint64 runId = run["id"].toVariant().toLongLong();
                QString headBranch = run["head_branch"].toString();
                QString createdAt = run["created_at"].toString();

                // Fetch artifacts for this run
                QString urlStr = QString("%1/repos/%2/%3/actions/runs/%4/artifacts")
                                     .arg(API_BASE_URL, owner, repo, QString::number(runId));

                QNetworkRequest request = createAuthenticatedRequest(QUrl(urlStr));
                QNetworkReply *artifactReply = _networkManager.get(request);

                _pendingRequests[artifactReply] = RequestWorkflowArtifacts;
                _requestMetadata[artifactReply] = qMakePair(owner, repo);

                // Store run info for when the artifact response comes back
                RunInfo info;
                info.owner = owner;
                info.repo = repo;
                info.branch = headBranch;
                info.createdAt = createdAt;
                info.runId = runId;
                _artifactRunInfo[artifactReply] = info;

                connect(artifactReply, &QNetworkReply::finished, this, [this, artifactReply]() {
                    handleNetworkReply(artifactReply);
                });
            }
        }
        break;
    }
    }
}

QNetworkRequest GitHubClient::createAuthenticatedRequest(const QUrl &url, int timeoutMs)
{
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, "Laerdal-SimServer-Imager");
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setRawHeader("X-GitHub-Api-Version", "2022-11-28");

    // Set connection/transfer timeout (covers connection establishment)
    request.setTransferTimeout(timeoutMs);

    if (!_authToken.isEmpty()) {
        request.setRawHeader("Authorization", QString("Bearer %1").arg(_authToken).toUtf8());
    }

    return request;
}

void GitHubClient::checkRateLimitHeaders(QNetworkReply *reply)
{
    QString remaining = reply->rawHeader("X-RateLimit-Remaining");
    QString limit = reply->rawHeader("X-RateLimit-Limit");
    QString reset = reply->rawHeader("X-RateLimit-Reset");

    if (!remaining.isEmpty() && !limit.isEmpty()) {
        int remainingInt = remaining.toInt();
        int limitInt = limit.toInt();
        qint64 resetTime = reset.toLongLong();

        if (remainingInt < 10) {
            qWarning() << "GitHubClient: Rate limit low:" << remainingInt << "/" << limitInt;
        }

        if (remainingInt == 0) {
            QDateTime resetDateTime = QDateTime::fromSecsSinceEpoch(resetTime);
            qWarning() << "GitHubClient: Rate limit exceeded, resets at" << resetDateTime.toString();
            emit rateLimitExceeded(resetTime);
        }
    }
}

QJsonArray GitHubClient::filterWicAssets(const QJsonArray &releases, const QString &owner, const QString &repo)
{
    QJsonArray wicFiles;

    // Image file extensions to look for (WIC, VSI, SPU)
    QStringList fileExtensions = {".wic", ".wic.gz", ".wic.xz", ".wic.zst", ".wic.bz2", ".vsi", ".spu"};

    for (const auto &releaseValue : releases) {
        QJsonObject release = releaseValue.toObject();
        QString tagName = release["tag_name"].toString();
        QString releaseName = release["name"].toString();
        bool prerelease = release["prerelease"].toBool();
        QString publishedAt = release["published_at"].toString();

        QJsonArray assets = release["assets"].toArray();

        for (const auto &assetValue : assets) {
            QJsonObject asset = assetValue.toObject();
            QString name = asset["name"].toString();

            // Check if it's a WIC file
            bool isWic = false;
            for (const QString &ext : fileExtensions) {
                if (name.endsWith(ext, Qt::CaseInsensitive)) {
                    isWic = true;
                    break;
                }
            }

            if (isWic) {
                QJsonObject wicFile;
                wicFile["name"] = name;
                wicFile["tag"] = tagName;
                wicFile["release_name"] = releaseName;
                wicFile["prerelease"] = prerelease;
                wicFile["published_at"] = publishedAt;
                wicFile["size"] = asset["size"].toVariant().toLongLong();
                wicFile["download_url"] = asset["browser_download_url"].toString();
                wicFile["asset_id"] = asset["id"].toVariant().toLongLong();
                wicFile["content_type"] = asset["content_type"].toString();
                wicFile["owner"] = owner;
                wicFile["repo"] = repo;

                wicFiles.append(wicFile);
            }
        }
    }

    qDebug() << "GitHubClient: Found" << wicFiles.size() << "WIC files in releases";
    return wicFiles;
}

QJsonArray GitHubClient::filterWicArtifacts(const QJsonArray &artifacts,
                                             const QString &owner, const QString &repo,
                                             const QString &branch, const QString &runCreatedAt)
{
    QJsonArray wicFiles;

    // Image file extensions to look for in artifact names (WIC, VSI, SPU)
    QStringList fileExtensions = {".wic", ".wic.gz", ".wic.xz", ".wic.zst", ".wic.bz2", ".vsi", ".spu"};
    // Also check for artifact names that suggest image content (ZIP files containing WIC/VSI/SPU files)
    // Note: "build-artifacts-spu" = SimPad images, "build-artifacts-sdk" = Yocto SDK (excluded)
    QStringList wicPatterns = {"wic", "image", "firmware", "build-artifacts-spu"};

    qDebug() << "GitHubClient: Filtering" << artifacts.size() << "artifacts for WIC files";

    for (const auto &artifactValue : artifacts) {
        QJsonObject artifact = artifactValue.toObject();
        QString name = artifact["name"].toString();
        qint64 artifactId = artifact["id"].toVariant().toLongLong();
        qint64 size = artifact["size_in_bytes"].toVariant().toLongLong();
        bool expired = artifact["expired"].toBool();

        qDebug() << "GitHubClient: Checking artifact:" << name << "expired:" << expired << "size:" << size;

        if (expired) {
            continue;  // Skip expired artifacts
        }

        // Check if artifact name suggests it contains WIC files
        bool isWicArtifact = false;
        QString nameLower = name.toLower();

        // Check for WIC extensions in name
        for (const QString &ext : fileExtensions) {
            if (nameLower.contains(ext)) {
                isWicArtifact = true;
                break;
            }
        }

        // Check for WIC-related patterns if not already matched
        if (!isWicArtifact) {
            for (const QString &pattern : wicPatterns) {
                if (nameLower.contains(pattern)) {
                    isWicArtifact = true;
                    break;
                }
            }
        }

        if (isWicArtifact) {
            QJsonObject wicFile;
            wicFile["name"] = name;
            wicFile["artifact_id"] = artifactId;
            wicFile["size"] = size;
            wicFile["branch"] = branch;
            wicFile["created_at"] = runCreatedAt;
            wicFile["owner"] = owner;
            wicFile["repo"] = repo;
            wicFile["download_url"] = getArtifactDownloadUrl(owner, repo, artifactId);
            wicFile["source"] = "artifact";  // Distinguish from release assets

            wicFiles.append(wicFile);
        }
    }

    qDebug() << "GitHubClient: Found" << wicFiles.size() << "WIC artifacts";
    return wicFiles;
}

// Partial artifact download support

bool GitHubClient::hasPartialArtifactDownload() const
{
    return _partialArtifactDownload.isValid;
}

QVariantMap GitHubClient::getPartialArtifactDownloadInfo() const
{
    QVariantMap info;
    if (!_partialArtifactDownload.isValid) {
        return info;
    }

    info["artifactName"] = _partialArtifactDownload.artifactName;
    info["artifactId"] = _partialArtifactDownload.artifactId;
    info["bytesDownloaded"] = _partialArtifactDownload.bytesDownloaded;
    info["totalSize"] = _partialArtifactDownload.totalSize;
    info["owner"] = _partialArtifactDownload.owner;
    info["repo"] = _partialArtifactDownload.repo;
    info["branch"] = _partialArtifactDownload.branch;

    double percentComplete = 0;
    if (_partialArtifactDownload.totalSize > 0) {
        percentComplete = (double)_partialArtifactDownload.bytesDownloaded * 100.0 /
                          (double)_partialArtifactDownload.totalSize;
    }
    info["percentComplete"] = percentComplete;

    return info;
}

void GitHubClient::resumeArtifactDownload()
{
    if (!_partialArtifactDownload.isValid) {
        qDebug() << "GitHubClient: No partial artifact download to resume";
        return;
    }

    qDebug() << "GitHubClient: Resuming artifact download from"
             << _partialArtifactDownload.bytesDownloaded << "bytes";

    // Re-trigger the download with resume support
    inspectArtifactContents(_partialArtifactDownload.owner,
                            _partialArtifactDownload.repo,
                            _partialArtifactDownload.artifactId,
                            _partialArtifactDownload.artifactName,
                            _partialArtifactDownload.branch);
}

void GitHubClient::discardPartialArtifactDownload()
{
    qDebug() << "GitHubClient: Discarding partial artifact download";

    // Delete the partial file
    if (!_partialArtifactDownload.partialPath.isEmpty() &&
        QFile::exists(_partialArtifactDownload.partialPath)) {
        QFile::remove(_partialArtifactDownload.partialPath);
    }

    clearPartialArtifactDownload();
}

void GitHubClient::savePartialArtifactDownload()
{
    QSettings settings;
    settings.beginGroup("github");
    settings.beginGroup("partialArtifact");
    settings.setValue("partialPath", _partialArtifactDownload.partialPath);
    settings.setValue("finalPath", _partialArtifactDownload.finalPath);
    settings.setValue("owner", _partialArtifactDownload.owner);
    settings.setValue("repo", _partialArtifactDownload.repo);
    settings.setValue("branch", _partialArtifactDownload.branch);
    settings.setValue("artifactName", _partialArtifactDownload.artifactName);
    settings.setValue("artifactId", _partialArtifactDownload.artifactId);
    settings.setValue("bytesDownloaded", _partialArtifactDownload.bytesDownloaded);
    settings.setValue("totalSize", _partialArtifactDownload.totalSize);
    settings.setValue("downloadUrl", _partialArtifactDownload.downloadUrl.toString());
    settings.endGroup();
    settings.endGroup();
    settings.sync();

    qDebug() << "GitHubClient: Saved partial artifact download state";
}

void GitHubClient::loadPartialArtifactDownload()
{
    QSettings settings;
    settings.beginGroup("github");
    settings.beginGroup("partialArtifact");

    QString partialPath = settings.value("partialPath").toString();
    qint64 bytesDownloaded = settings.value("bytesDownloaded", 0).toLongLong();

    settings.endGroup();
    settings.endGroup();

    // Validate the partial file exists and has expected size
    if (!partialPath.isEmpty() && bytesDownloaded > 0) {
        QFileInfo fileInfo(partialPath);
        if (fileInfo.exists() && fileInfo.size() == bytesDownloaded) {
            settings.beginGroup("github");
            settings.beginGroup("partialArtifact");

            _partialArtifactDownload.partialPath = partialPath;
            _partialArtifactDownload.finalPath = settings.value("finalPath").toString();
            _partialArtifactDownload.owner = settings.value("owner").toString();
            _partialArtifactDownload.repo = settings.value("repo").toString();
            _partialArtifactDownload.branch = settings.value("branch").toString();
            _partialArtifactDownload.artifactName = settings.value("artifactName").toString();
            _partialArtifactDownload.artifactId = settings.value("artifactId", 0).toLongLong();
            _partialArtifactDownload.bytesDownloaded = bytesDownloaded;
            _partialArtifactDownload.totalSize = settings.value("totalSize", 0).toLongLong();
            _partialArtifactDownload.downloadUrl = QUrl(settings.value("downloadUrl").toString());
            _partialArtifactDownload.isValid = true;

            settings.endGroup();
            settings.endGroup();

            qDebug() << "GitHubClient: Loaded partial artifact download:"
                     << _partialArtifactDownload.artifactName
                     << _partialArtifactDownload.bytesDownloaded << "/"
                     << _partialArtifactDownload.totalSize << "bytes";
        } else {
            qDebug() << "GitHubClient: Partial artifact file missing or size mismatch, clearing";
            clearPartialArtifactDownload();
        }
    }
}

void GitHubClient::clearPartialArtifactDownload()
{
    _partialArtifactDownload = PartialArtifactDownload();

    QSettings settings;
    settings.beginGroup("github");
    settings.beginGroup("partialArtifact");
    settings.remove("");  // Remove all keys in this group
    settings.endGroup();
    settings.endGroup();
    settings.sync();
}
