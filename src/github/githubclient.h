/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#ifndef GITHUBCLIENT_H
#define GITHUBCLIENT_H

#include <QObject>
#include <QString>
#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>

#ifndef CLI_ONLY_BUILD
#include <QQmlEngine>
#endif

/**
 * @brief GitHub API client for fetching releases and files
 *
 * Provides methods to:
 * - Fetch releases from a repository
 * - Get raw file content from specific branches/tags
 * - List WIC files from releases
 */
class GitHubClient : public QObject
{
    Q_OBJECT
#ifndef CLI_ONLY_BUILD
    QML_ELEMENT
    QML_UNCREATABLE("Created by C++")
#endif

public:
    explicit GitHubClient(QObject *parent = nullptr);
    virtual ~GitHubClient();

    /**
     * @brief Set the authentication token
     * @param token GitHub personal access token or OAuth token
     */
    Q_INVOKABLE void setAuthToken(const QString &token);

    /**
     * @brief Check if authenticated
     */
    Q_INVOKABLE bool isAuthenticated() const { return !_authToken.isEmpty(); }

    /**
     * @brief Fetch releases from a repository
     * @param owner Repository owner (organization or user)
     * @param repo Repository name
     */
    Q_INVOKABLE void fetchReleases(const QString &owner, const QString &repo);

    /**
     * @brief Fetch a file from a specific branch
     * @param owner Repository owner
     * @param repo Repository name
     * @param branch Branch name
     * @param path File path within the repository
     */
    Q_INVOKABLE void fetchBranchFile(const QString &owner, const QString &repo,
                                      const QString &branch, const QString &path);

    /**
     * @brief Fetch a file from a specific tag
     * @param owner Repository owner
     * @param repo Repository name
     * @param tag Tag name
     * @param path File path within the repository
     */
    Q_INVOKABLE void fetchTagFile(const QString &owner, const QString &repo,
                                   const QString &tag, const QString &path);

    /**
     * @brief Fetch repository info (including default branch)
     * @param owner Repository owner
     * @param repo Repository name
     */
    Q_INVOKABLE void fetchRepoInfo(const QString &owner, const QString &repo);

    /**
     * @brief List branches for a repository
     * @param owner Repository owner
     * @param repo Repository name
     */
    Q_INVOKABLE void fetchBranches(const QString &owner, const QString &repo);

    /**
     * @brief List tags for a repository
     * @param owner Repository owner
     * @param repo Repository name
     */
    Q_INVOKABLE void fetchTags(const QString &owner, const QString &repo);

    /**
     * @brief Search for WIC files in a repository's releases
     * @param owner Repository owner
     * @param repo Repository name
     */
    Q_INVOKABLE void searchWicFilesInReleases(const QString &owner, const QString &repo);

    /**
     * @brief Fetch workflow runs for a repository
     * @param owner Repository owner
     * @param repo Repository name
     * @param branch Optional branch filter
     * @param status Optional status filter (e.g., "success", "completed")
     */
    Q_INVOKABLE void fetchWorkflowRuns(const QString &owner, const QString &repo,
                                        const QString &branch = QString(),
                                        const QString &status = "success");

    /**
     * @brief Fetch artifacts for a specific workflow run
     * @param owner Repository owner
     * @param repo Repository name
     * @param runId Workflow run ID
     */
    Q_INVOKABLE void fetchWorkflowArtifacts(const QString &owner, const QString &repo, qint64 runId);

    /**
     * @brief Search for WIC files in workflow artifacts
     * @param owner Repository owner
     * @param repo Repository name
     * @param branch Optional branch filter
     */
    Q_INVOKABLE void searchWicFilesInArtifacts(const QString &owner, const QString &repo,
                                                const QString &branch = QString());

    /**
     * @brief Get the download URL for a release asset
     * @param owner Repository owner
     * @param repo Repository name
     * @param assetId Asset ID
     * @return Download URL with authentication
     */
    Q_INVOKABLE QString getAssetDownloadUrl(const QString &owner, const QString &repo, qint64 assetId);

    /**
     * @brief Get the download URL for a workflow artifact
     * @param owner Repository owner
     * @param repo Repository name
     * @param artifactId Artifact ID
     * @return Download URL with authentication
     */
    Q_INVOKABLE QString getArtifactDownloadUrl(const QString &owner, const QString &repo, qint64 artifactId);

    /**
     * @brief Get rate limit information
     */
    Q_INVOKABLE void checkRateLimit();

    /**
     * @brief Download an artifact ZIP file to a local path
     * @param owner Repository owner
     * @param repo Repository name
     * @param artifactId Artifact ID
     * @param destinationPath Local path to save the ZIP file
     */
    Q_INVOKABLE void downloadArtifact(const QString &owner, const QString &repo,
                                       qint64 artifactId, const QString &destinationPath);

    /**
     * @brief Get the authentication token for use by other components
     * @return The current auth token (empty if not authenticated)
     */
    QString authToken() const { return _authToken; }

    /**
     * @brief Download an artifact and inspect its contents for WIC files
     * @param owner Repository owner
     * @param repo Repository name
     * @param artifactId Artifact ID
     * @param artifactName Original artifact name for display
     * @param branch Branch name the artifact came from
     *
     * Downloads the artifact ZIP to a temporary location and emits
     * artifactContentsReady with the list of WIC files found.
     */
    Q_INVOKABLE void inspectArtifactContents(const QString &owner, const QString &repo,
                                              qint64 artifactId, const QString &artifactName,
                                              const QString &branch);

    /**
     * @brief Cancel any ongoing artifact inspection download
     */
    Q_INVOKABLE void cancelArtifactInspection();

    /**
     * @brief Download an artifact and inspect its contents for SPU files
     * @param owner Repository owner
     * @param repo Repository name
     * @param artifactId Artifact ID
     * @param artifactName Original artifact name for display
     * @param branch Branch name the artifact came from
     *
     * Downloads the artifact ZIP to a temporary location and emits
     * artifactSpuContentsReady with the list of SPU files found.
     */
    Q_INVOKABLE void inspectArtifactSpuContents(const QString &owner, const QString &repo,
                                                 qint64 artifactId, const QString &artifactName,
                                                 const QString &branch);

signals:
    /**
     * @brief Emitted when artifact inspection is cancelled
     */
    void artifactInspectionCancelled();
    /**
     * @brief Emitted when artifact download is complete
     * @param localPath Path to the downloaded ZIP file
     */
    void artifactDownloadComplete(const QString &localPath);

    /**
     * @brief Emitted during artifact download with progress
     * @param bytesReceived Bytes downloaded so far
     * @param bytesTotal Total bytes to download (-1 if unknown)
     */
    void artifactDownloadProgress(qint64 bytesReceived, qint64 bytesTotal);
    /**
     * @brief Emitted when releases are fetched successfully
     * @param releases Array of release objects
     */
    void releasesReady(const QJsonArray &releases);

    /**
     * @brief Emitted when a file URL is ready for download
     * @param downloadUrl URL to download the file
     * @param fileName Original file name
     */
    void fileUrlReady(const QString &downloadUrl, const QString &fileName);

    /**
     * @brief Emitted when repository info is fetched
     * @param owner Repository owner
     * @param repo Repository name
     * @param defaultBranch Default branch name
     */
    void repoInfoReady(const QString &owner, const QString &repo, const QString &defaultBranch);

    /**
     * @brief Emitted when branches are fetched
     * @param branches Array of branch names
     */
    void branchesReady(const QJsonArray &branches);

    /**
     * @brief Emitted when tags are fetched
     * @param tags Array of tag names
     */
    void tagsReady(const QJsonArray &tags);

    /**
     * @brief Emitted when WIC files are found in releases
     * @param wicFiles Array of WIC file information objects
     */
    void wicFilesReady(const QJsonArray &wicFiles);

    /**
     * @brief Emitted when workflow runs are fetched
     * @param runs Array of workflow run objects
     */
    void workflowRunsReady(const QJsonArray &runs);

    /**
     * @brief Emitted when workflow artifacts are fetched
     * @param artifacts Array of artifact objects
     */
    void workflowArtifactsReady(const QJsonArray &artifacts);

    /**
     * @brief Emitted when WIC files are found in artifacts
     * @param wicFiles Array of WIC file information objects from artifacts
     */
    void artifactWicFilesReady(const QJsonArray &wicFiles);

    /**
     * @brief Emitted when artifact contents have been inspected
     * @param artifactId The artifact ID that was inspected
     * @param artifactName The original artifact name
     * @param owner Repository owner
     * @param repo Repository name
     * @param branch Branch name
     * @param wicFiles Array of WIC file info objects found in the artifact
     * @param zipPath Path to the downloaded ZIP file (for later extraction)
     */
    void artifactContentsReady(qint64 artifactId, const QString &artifactName,
                                const QString &owner, const QString &repo,
                                const QString &branch, const QJsonArray &wicFiles,
                                const QString &zipPath);

    /**
     * @brief Emitted when artifact SPU contents have been inspected
     * @param artifactId The artifact ID that was inspected
     * @param artifactName The original artifact name
     * @param owner Repository owner
     * @param repo Repository name
     * @param branch Branch name
     * @param spuFiles Array of SPU file info objects found in the artifact
     * @param zipPath Path to the downloaded ZIP file (for later extraction)
     */
    void artifactSpuContentsReady(qint64 artifactId, const QString &artifactName,
                                   const QString &owner, const QString &repo,
                                   const QString &branch, const QJsonArray &spuFiles,
                                   const QString &zipPath);

    /**
     * @brief Emitted on API error
     * @param message Error message
     */
    void error(const QString &message);

    /**
     * @brief Emitted when rate limit is exceeded
     * @param resetTime Unix timestamp when rate limit resets
     */
    void rateLimitExceeded(qint64 resetTime);

    /**
     * @brief Emitted with rate limit information
     * @param remaining Remaining requests
     * @param limit Total limit
     * @param resetTime Reset timestamp
     */
    void rateLimitInfo(int remaining, int limit, qint64 resetTime);

private slots:
    void handleNetworkReply(QNetworkReply *reply);

private:
    QNetworkRequest createAuthenticatedRequest(const QUrl &url, int timeoutMs = API_TIMEOUT_MS);
    void checkRateLimitHeaders(QNetworkReply *reply);
    QJsonArray filterWicAssets(const QJsonArray &releases, const QString &owner, const QString &repo);
    QJsonArray filterWicArtifacts(const QJsonArray &artifacts,
                                   const QString &owner, const QString &repo,
                                   const QString &branch, const QString &runCreatedAt);
    void downloadArtifactFromUrl(const QUrl &url, const QString &destinationPath);
    void inspectArtifactFromUrl(const QUrl &url, const QString &owner, const QString &repo,
                                 qint64 artifactId, const QString &artifactName,
                                 const QString &branch, const QString &zipPath);
    QJsonArray listWicFilesInZip(const QString &zipPath);
    QJsonArray listSpuFilesInZip(const QString &zipPath);
    QJsonArray listImageFilesInZip(const QString &zipPath);  // Combined WIC + SPU
    void inspectArtifactSpuFromUrl(const QUrl &url, const QString &owner, const QString &repo,
                                    qint64 artifactId, const QString &artifactName,
                                    const QString &branch, const QString &zipPath);

    static constexpr const char* API_BASE_URL = "https://api.github.com";
    static constexpr const char* RAW_BASE_URL = "https://raw.githubusercontent.com";

    // Timeouts in milliseconds
    static constexpr int API_TIMEOUT_MS = 30000;  // 30 seconds for API calls

    QNetworkAccessManager _networkManager;
    QString _authToken;

    // Track pending requests
    enum RequestType {
        RequestReleases,
        RequestRepoInfo,
        RequestBranches,
        RequestTags,
        RequestFile,
        RequestRateLimit,
        RequestWicSearch,
        RequestWorkflowRuns,
        RequestWorkflowArtifacts,
        RequestArtifactWicSearch
    };

    QHash<QNetworkReply*, RequestType> _pendingRequests;
    QHash<QNetworkReply*, QPair<QString, QString>> _requestMetadata; // owner/repo

    // State for artifact WIC search (requires multiple API calls)
    struct ArtifactSearchState {
        QString owner;
        QString repo;
        int pendingRuns = 0;
        QJsonArray collectedArtifacts;
    };
    QHash<QString, ArtifactSearchState> _artifactSearchStates; // key: "owner/repo"

    // Map reply to run info for artifact fetches
    struct RunInfo {
        QString owner;
        QString repo;
        QString branch;
        QString createdAt;
        qint64 runId;
    };
    QHash<QNetworkReply*, RunInfo> _artifactRunInfo;

    // Track ongoing artifact inspection download for cancellation
    QNetworkReply *_activeInspectionReply = nullptr;
    QString _activeInspectionZipPath;  // Path to delete on cancellation
};

#endif // GITHUBCLIENT_H
