/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#ifndef GITHUBSOURCE_H
#define GITHUBSOURCE_H

#include <QObject>
#include <QString>
#include <QJsonArray>

class GitHubClient;

/**
 * @brief Handles WIC file discovery from a specific GitHub repository
 *
 * This class manages fetching WIC files from:
 * - GitHub Releases (assets)
 * - Specific branches/tags (raw file URLs)
 */
class GitHubSource : public QObject
{
    Q_OBJECT

public:
    explicit GitHubSource(const QString &owner, const QString &repo,
                          QObject *parent = nullptr);
    virtual ~GitHubSource();

    QString owner() const { return _owner; }
    QString repo() const { return _repo; }
    QString fullName() const { return QString("%1/%2").arg(_owner, _repo); }

    QString defaultBranch() const { return _defaultBranch; }
    void setDefaultBranch(const QString &branch) { _defaultBranch = branch; }

    bool isEnabled() const { return _enabled; }
    void setEnabled(bool enabled) { _enabled = enabled; }

    /**
     * @brief Set the GitHub client for API access
     */
    void setGitHubClient(GitHubClient *client);

    /**
     * @brief Search for WIC files in releases
     */
    void searchReleasesForWicFiles();

    /**
     * @brief Search for WIC files in workflow artifacts
     * @param branch Optional branch filter
     */
    void searchArtifactsForWicFiles(const QString &branch = QString());

    /**
     * @brief Get WIC file URL from a specific branch
     * @param branch Branch name
     * @param path Path to the WIC file in the repo
     */
    void getFileFromBranch(const QString &branch, const QString &path);

    /**
     * @brief Get WIC file URL from a specific tag
     * @param tag Tag name
     * @param path Path to the WIC file in the repo
     */
    void getFileFromTag(const QString &tag, const QString &path);

    /**
     * @brief Get cached list of WIC files found
     */
    QJsonArray getWicFiles() const { return _wicFiles; }

signals:
    /**
     * @brief Emitted when WIC files are found in releases
     * @param wicFiles Array of WIC file entries
     */
    void wicFilesReady(const QJsonArray &wicFiles);

    /**
     * @brief Emitted when WIC files are found in artifacts
     * @param wicFiles Array of WIC file entries from artifacts
     */
    void artifactWicFilesReady(const QJsonArray &wicFiles);

    /**
     * @brief Emitted when a file URL is ready
     * @param downloadUrl URL to download
     * @param fileName File name
     */
    void fileReady(const QString &downloadUrl, const QString &fileName);

    /**
     * @brief Emitted on error
     * @param message Error message
     */
    void error(const QString &message);

private slots:
    void onWicFilesReceived(const QJsonArray &wicFiles);
    void onArtifactWicFilesReceived(const QJsonArray &wicFiles);
    void onFileUrlReceived(const QString &downloadUrl, const QString &fileName);
    void onError(const QString &message);

private:
    QString _owner;
    QString _repo;
    QString _defaultBranch = "main";
    bool _enabled = true;

    GitHubClient *_githubClient = nullptr;
    QJsonArray _wicFiles;
};

#endif // GITHUBSOURCE_H
