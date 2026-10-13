/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#include "downloadonly.h"
#include "curlnetworkconfig.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <archive.h>
#include <archive_entry.h>
#include <array>
#include <functional>
#include <memory>
#include <utility>

namespace {
struct Transfer {
    QIODevice *output;
    std::atomic<bool> *cancelled;
    std::function<void(qint64, qint64)> progress;
    QElapsedTimer timer;
    QString error;
};

size_t writeData(char *data, size_t size, size_t count, void *opaque)
{
    auto &transfer = *static_cast<Transfer *>(opaque);
    const auto bytes = static_cast<qint64>(size * count);
    if (transfer.cancelled->load()) return 0;
    if (transfer.output->write(data, bytes) != bytes) {
        transfer.error = transfer.output->errorString();
        return 0;
    }
    return static_cast<size_t>(bytes);
}

int reportProgress(void *opaque, curl_off_t total, curl_off_t received, curl_off_t, curl_off_t)
{
    auto &transfer = *static_cast<Transfer *>(opaque);
    if (transfer.cancelled->load()) return 1;
    if (transfer.timer.elapsed() >= 100) {
        transfer.progress(received, total);
        transfer.timer.restart();
    }
    return 0;
}

QString fetch(const QUrl &url, QIODevice &output, const QString &token,
              std::atomic<bool> &cancelled, const std::function<void(qint64, qint64)> &progress)
{
    if (url.scheme() != "https" && url.scheme() != "http")
        return DownloadOnly::tr("Unsupported download URL.");
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(), curl_easy_cleanup);
    if (!curl) return DownloadOnly::tr("Could not initialize the download.");
    char error[CURL_ERROR_SIZE] = {};
    CurlNetworkConfig::instance().applyCurlSettings(curl.get(), CurlNetworkConfig::FetchProfile::LargeFile, error);
    const QByteArray encoded = url.toEncoded();
    curl_easy_setopt(curl.get(), CURLOPT_URL, encoded.constData());
    // Never forward GitHub credentials to redirected object-storage hosts.
    curl_easy_setopt(curl.get(), CURLOPT_UNRESTRICTED_AUTH, 0L);
    curl_easy_setopt(curl.get(), CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(curl.get(), CURLOPT_REDIR_PROTOCOLS_STR, url.scheme() == "https" ? "https" : "http,https");
    Transfer transfer{&output, &cancelled, progress, {}, {}};
    transfer.timer.start();
    curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION, writeData);
    curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, &transfer);
    curl_easy_setopt(curl.get(), CURLOPT_XFERINFOFUNCTION, reportProgress);
    curl_easy_setopt(curl.get(), CURLOPT_XFERINFODATA, &transfer);
    curl_easy_setopt(curl.get(), CURLOPT_NOPROGRESS, 0L);
    curl_slist *headers = nullptr;
    if (url.host() == "api.github.com") {
        headers = curl_slist_append(headers, "Accept: application/octet-stream");
        if (!token.isEmpty())
            headers = curl_slist_append(headers, ("Authorization: Bearer " + token).toUtf8().constData());
        curl_easy_setopt(curl.get(), CURLOPT_HTTPHEADER, headers);
    }
    const CURLcode result = curl_easy_perform(curl.get());
    curl_slist_free_all(headers);
    if (!transfer.error.isEmpty()) return transfer.error;
    if (result != CURLE_OK) return QString::fromUtf8(error[0] ? error : curl_easy_strerror(result));
    return {};
}

QString extract(const QString &zip, const QString &entryName, bool matchBasename, QSaveFile &output,
                std::atomic<bool> &cancelled, const std::function<void(qint64, qint64)> &progress)
{
    std::unique_ptr<archive, decltype(&archive_read_free)> reader(archive_read_new(), archive_read_free);
    archive_read_support_format_zip(reader.get());
    const auto archiveError = [&]() {
        const char *message = archive_error_string(reader.get());
        return message ? QString::fromUtf8(message) : DownloadOnly::tr("Could not read the artifact ZIP.");
    };
    if (archive_read_open_filename(reader.get(), QFile::encodeName(zip).constData(), 256 * 1024) != ARCHIVE_OK)
        return archiveError();
    archive_entry *entry = nullptr;
    bool found = false;
    int result;
    std::array<char, 256 * 1024> buffer;
    while ((result = archive_read_next_header(reader.get(), &entry)) == ARCHIVE_OK) {
        if (cancelled.load()) return {};
        const char *pathname = archive_entry_pathname_utf8(entry);
        if (!pathname) pathname = archive_entry_pathname(entry);
        const QString name = QString::fromUtf8(pathname ? pathname : "");
        const bool matches = matchBasename ? QFileInfo(name).fileName() == entryName : name == entryName;
        if (!matches) {
            if (archive_read_data_skip(reader.get()) != ARCHIVE_OK) return archiveError();
            continue;
        }
        if (found) return DownloadOnly::tr("The artifact contains ambiguous duplicate image filenames.");
        if (archive_entry_filetype(entry) != AE_IFREG || archive_entry_symlink(entry) || archive_entry_hardlink(entry))
            return DownloadOnly::tr("The selected archive entry is not a regular file.");
        found = true;
        qint64 received = 0;
        const qint64 total = archive_entry_size(entry);
        QElapsedTimer timer;
        timer.start();
        la_ssize_t bytes;
        while ((bytes = archive_read_data(reader.get(), buffer.data(), buffer.size())) > 0) {
            if (cancelled.load()) return {};
            if (output.write(buffer.data(), bytes) != bytes) return output.errorString();
            received += bytes;
            if (timer.elapsed() >= 100) {
                progress(received, total);
                timer.restart();
            }
        }
        if (bytes < 0) return archiveError();
        if (total >= 0 && received != total)
            return DownloadOnly::tr("The selected image is incomplete.");
        progress(received, total);
    }
    if (result != ARCHIVE_EOF) return archiveError();
    return found ? QString() : DownloadOnly::tr("The selected image file was not found in the artifact.");
}
}

DownloadOnly::DownloadOnly(QObject *parent) : QObject(parent) {}

DownloadOnly::~DownloadOnly()
{
    cancel();
    if (_worker) {
        _worker->wait();
        delete _worker;
    }
}

void DownloadOnly::cancel() { _cancelled.store(true); }

bool DownloadOnly::destinationExists(const QUrl &destination) const
{
    return QFileInfo::exists(destination.toLocalFile()) || QFileInfo(destination.toLocalFile()).isSymLink();
}

QString DownloadOnly::suggestedFilename(const QVariantMap &source) const
{
    QString name = source.value("filename").toString();
    if (name.isEmpty()) name = QUrl(source.value("url").toString()).fileName(QUrl::FullyDecoded);
    name.replace('\\', '/');
    name = name.section('/', -1);
    name.remove(QChar('\0'));
    return name.isEmpty() || name == "." || name == ".." ? QStringLiteral("image.wic") : name;
}

void DownloadOnly::progress(qint64 received, qint64 total, const QString &status)
{
    QMetaObject::invokeMethod(this, [this, received, total, status] {
        _received = received;
        _total = total;
        _status = status;
        emit changed();
    }, Qt::QueuedConnection);
}

void DownloadOnly::start(const QVariantMap &source, const QUrl &destination, const QString &token, bool overwrite)
{
    if (_busy) return;
    if (_worker) {
        _worker->wait();
        delete _worker;
        _worker = nullptr;
    }
    _cancelled.store(false);
    _busy = true;
    _received = _total = 0;
    _error.clear();
    _savedFile.clear();
    _status = tr("Connecting…");
    emit changed();
    _worker = QThread::create([this, source, destination, token, overwrite] {
        QString error;
        const QString path = destination.toLocalFile();
        const QFileInfo info(path);
        if (!destination.isLocalFile() || path.isEmpty() || !QFileInfo(info.absolutePath()).isDir())
            error = tr("Choose a file in an existing local folder.");
        else if (info.isSymLink() || (info.exists() && !info.isFile()))
            error = tr("The destination must be a regular file, not a device or symbolic link.");
        else if (info.exists() && !overwrite)
            error = tr("The destination already exists. Choose another filename or confirm replacement.");
        QSaveFile output(path);
        output.setDirectWriteFallback(false);
        if (error.isEmpty() && !output.open(QIODevice::WriteOnly)) error = output.errorString();
        const auto downloading = [this](qint64 received, qint64 total) { progress(received, total, tr("Downloading…")); };
        const auto extracting = [this](qint64 received, qint64 total) { progress(received, total, tr("Saving selected image…")); };
        const qint64 artifactId = source.value("artifact_id").toLongLong();
        const QUrl url(source.value("url").toString());
        // Scratch ZIPs live beside the destination and are always removed, never in the system temp directory.
        QTemporaryFile zipFile(info.absolutePath() + "/.imager-artifact-XXXXXX");
        QString zip = source.value("zip_path").toString();
        const QString entry = source.value("entry").toString();
        if (error.isEmpty() && artifactId > 0 && entry.isEmpty())
            error = tr("Select an image file from the artifact before downloading.");
        if (error.isEmpty() && !entry.isEmpty()) {
            if (zip.isEmpty()) {
                if (!zipFile.open()) error = zipFile.errorString();
                else {
                    error = fetch(url, zipFile, token, _cancelled, downloading);
                    if (error.isEmpty() && !zipFile.flush()) error = zipFile.errorString();
                    zip = zipFile.fileName();
                    zipFile.close();
                }
            }
            if (error.isEmpty() && !_cancelled.load())
                error = extract(zip, entry, source.value("match_basename").toBool(), output, _cancelled, extracting);
        } else if (error.isEmpty() && url.isLocalFile()) {
            QFile input(url.toLocalFile());
            if (!input.open(QIODevice::ReadOnly)) error = input.errorString();
            else {
                std::array<char, 256 * 1024> buffer;
                qint64 received = 0, bytes;
                QElapsedTimer timer;
                timer.start();
                while (!_cancelled.load() && (bytes = input.read(buffer.data(), buffer.size())) > 0) {
                    if (output.write(buffer.data(), bytes) != bytes) { error = output.errorString(); break; }
                    received += bytes;
                    if (timer.elapsed() >= 100) { downloading(received, input.size()); timer.restart(); }
                }
                if (input.error() != QFile::NoError) error = input.errorString();
            }
        } else if (error.isEmpty()) {
            error = fetch(url, output, token, _cancelled, downloading);
        }
        bool cancelled = _cancelled.load();
        if (error.isEmpty() && !cancelled) {
            const QFileInfo current(path);
            if (current.isSymLink() || (current.exists() && (!current.isFile() || !overwrite)))
                error = tr("The destination changed while downloading. Choose another filename.");
            else if (!output.commit()) error = output.errorString();
        } else {
            output.cancelWriting();
        }
        QMetaObject::invokeMethod(this, [this, destination, error, cancelled] {
            _busy = false;
            _error = cancelled ? QString() : error;
            _status = cancelled ? tr("Download cancelled.") : error.isEmpty() ? tr("Download complete.") : tr("Download failed.");
            if (!cancelled && error.isEmpty()) _savedFile = destination;
            emit changed();
        }, Qt::QueuedConnection);
    });
    _worker->start();
}

bool DownloadOnly::openFolder(const QString &path)
{
    if (_folderLauncher && _folderLauncher(QUrl::fromLocalFile(path))) return true;
    _error = tr("Could not open the folder: %1").arg(path);
    emit changed();
    return false;
}

void DownloadOnly::setFolderLauncher(std::function<bool(const QUrl &)> launcher)
{
    _folderLauncher = std::move(launcher);
}

bool DownloadOnly::openContainingFolder()
{
    if (_savedFile.isEmpty()) return false;
    return openFolder(QFileInfo(_savedFile.toLocalFile()).absolutePath());
}

bool DownloadOnly::openCacheFolder()
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (!QDir().mkpath(path)) {
        _error = tr("Could not create the cache folder: %1").arg(path);
        emit changed();
        return false;
    }
    return openFolder(path);
}
