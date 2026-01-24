/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#ifndef SPUCOPYTHREAD_H
#define SPUCOPYTHREAD_H

#include <QThread>
#include <QString>
#include <QStringList>
#include <QByteArray>
#include <QUrl>

/**
 * @brief Thread for copying SPU files to FAT32-formatted USB drives
 *
 * Unlike WIC images (raw disk writes), SPU files are copied as regular files
 * to a mounted FAT32 filesystem.
 *
 * Flow:
 * 1. Optionally format drive to FAT32
 * 2. Mount the partition
 * 3. Extract SPU file from ZIP archive and copy to mount point
 * 4. Sync and unmount
 */
class SPUCopyThread : public QThread
{
    Q_OBJECT

public:
    /**
     * @brief Construct SPU copy thread
     * @param archivePath Path to the ZIP archive containing the SPU file
     * @param spuEntry Name of the SPU file entry within the ZIP
     * @param device Device path (e.g., "/dev/sdb" on Linux)
     * @param skipFormat If true, skip formatting (drive already FAT32)
     * @param parent Parent object
     */
    SPUCopyThread(const QString &archivePath, const QString &spuEntry,
                  const QByteArray &device, bool skipFormat = false,
                  QObject *parent = nullptr);

    /**
     * @brief Construct SPU copy thread for direct SPU file (not in ZIP)
     * @param spuFilePath Path to the SPU file
     * @param device Device path (e.g., "/dev/sdb" on Linux)
     * @param skipFormat If true, skip formatting (drive already FAT32)
     * @param parent Parent object
     */
    SPUCopyThread(const QString &spuFilePath, const QByteArray &device,
                  bool skipFormat, QObject *parent = nullptr);

    /**
     * @brief Construct SPU copy thread for URL download (from CDN or GitHub release)
     * Streams directly to FAT32 mount while caching.
     * @param url URL to download the SPU file from
     * @param device Device path (e.g., "/dev/sdb" on Linux)
     * @param skipFormat If true, skip formatting (drive already FAT32)
     * @param parent Parent object
     */
    SPUCopyThread(const QUrl &url, const QByteArray &device,
                  bool skipFormat, QObject *parent = nullptr);

    /**
     * @brief Construct SPU copy thread for artifact ZIP streaming (CI artifacts)
     * Downloads the ZIP, caches it, and extracts the target SPU entry to FAT32.
     * @param artifactUrl URL to download the artifact ZIP from
     * @param targetEntry Name of the SPU file entry within the ZIP
     * @param device Device path (e.g., "/dev/sdb" on Linux)
     * @param skipFormat If true, skip formatting (drive already FAT32)
     * @param parent Parent object
     */
    SPUCopyThread(const QUrl &artifactUrl, const QString &targetEntry,
                  const QByteArray &device, bool skipFormat,
                  QObject *parent = nullptr);

    virtual ~SPUCopyThread();

    /**
     * @brief Set HTTP auth token for URL downloads (e.g. GitHub private repo)
     * @param token OAuth or PAT token
     */
    void setAuthToken(const QString &token);

    /**
     * @brief Set the filename to use for downloaded file (overrides URL-derived name)
     * @param filename The desired filename (e.g. "image.spu")
     */
    void setDownloadFilename(const QString &filename);

    /**
     * @brief Set cache directory for caching downloads
     * @param cacheDir Directory to store cached files
     */
    void setCacheDir(const QString &cacheDir);

    /**
     * @brief Set HTTP headers for authenticated downloads (e.g. GitHub artifacts)
     * @param headers List of "Header-Name: value" strings
     */
    void setHttpHeaders(const QStringList &headers);

    /**
     * @brief Cancel the copy operation
     */
    void cancelCopy();

    /**
     * @brief Check if operation was cancelled
     */
    bool isCancelled() const { return _cancelled; }

signals:
    /**
     * @brief Emitted when copy completes successfully
     */
    void success();

    /**
     * @brief Emitted on error
     * @param msg Error message
     */
    void error(QString msg);

    /**
     * @brief Status update for preparation phases
     * @param msg Status message (e.g., "Formatting drive...", "Mounting...")
     */
    void preparationStatusUpdate(QString msg);

    /**
     * @brief Progress update for file copy
     * @param now Bytes copied so far
     * @param total Total bytes to copy
     */
    void copyProgress(quint64 now, quint64 total);

protected:
    void run() override;

private:
    /**
     * @brief Format the drive to FAT32
     * @return true on success
     */
    bool formatDrive();

    /**
     * @brief Mount the drive partition
     * @return Mount point path, empty on failure
     */
    QString mountDrive();

    /**
     * @brief Extract SPU from ZIP and copy to mount point
     * @param mountPoint Path where drive is mounted
     * @return true on success
     */
    bool extractAndCopy(const QString &mountPoint);

    /**
     * @brief Copy SPU file directly (not from ZIP)
     * @param mountPoint Path where drive is mounted
     * @return true on success
     */
    bool copyDirectFile(const QString &mountPoint);

    /**
     * @brief Stream SPU download directly to FAT32 mount and cache
     * @param mountPoint Path where drive is mounted
     * @return true on success
     */
    bool streamUrlToFile(const QString &mountPoint);

    /**
     * @brief Download artifact ZIP to cache and extract SPU entry to mount
     * @param mountPoint Path where drive is mounted
     * @return true on success
     */
    bool downloadArtifactAndCopy(const QString &mountPoint);

    /**
     * @brief Unmount the drive
     * @param mountPoint Path to unmount
     * @return true on success
     */
    bool unmountDrive(const QString &mountPoint);

    /**
     * @brief Delete existing SPU files from mount point
     * @param mountPoint Path where drive is mounted
     */
    void deleteExistingSpuFiles(const QString &mountPoint);

    QString _archivePath;       ///< Path to ZIP archive
    QString _spuEntry;          ///< SPU filename within ZIP
    QString _spuFilePath;       ///< Direct SPU file path (if not from ZIP)
    QUrl _spuUrl;               ///< URL to download SPU from (CDN or artifact)
    QByteArray _device;         ///< Device path
    bool _skipFormat;           ///< Skip formatting if drive is already FAT32
    bool _isDirectFile;         ///< True if copying direct SPU file (not from ZIP)
    bool _isUrlDownload;        ///< True if downloading from URL (standalone SPU)
    bool _isArtifactStreaming;  ///< True if streaming from CI artifact ZIP
    QString _artifactEntry;     ///< Target SPU entry name within artifact ZIP
    volatile bool _cancelled;   ///< Cancellation flag
    QString _authToken;         ///< OAuth token for authenticated downloads
    QString _downloadFilename;  ///< Override filename for downloaded file
    QString _cacheDir;          ///< Cache directory for storing downloads
    QStringList _httpHeaders;   ///< HTTP headers for authenticated requests
};

#endif // SPUCOPYTHREAD_H
