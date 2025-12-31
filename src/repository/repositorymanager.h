/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#ifndef REPOSITORYMANAGER_H
#define REPOSITORYMANAGER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QJsonArray>
#include <QJsonObject>
#include <QSettings>
#include <QVector>

#ifndef CLI_ONLY_BUILD
#include <QQmlEngine>
#endif

class GitHubClient;
class LaerdalCdnSource;
class GitHubSource;

/**
 * @brief Manages multiple image sources for the Laerdal SimServer Imager
 *
 * Supports:
 * - Laerdal CDN (different environments: production, test, dev, etc.)
 * - GitHub repositories (releases and branch/tag files)
 * - Local custom files
 */
class RepositoryManager : public QObject
{
    Q_OBJECT
#ifndef CLI_ONLY_BUILD
    QML_ELEMENT
    QML_UNCREATABLE("Created by C++")
#endif

public:
    /**
     * @brief Available Laerdal CDN environments
     */
    enum Environment {
        Production,
        Test,
        Dev,
        Beta,
        ReleaseCandidate
    };
    Q_ENUM(Environment)

    explicit RepositoryManager(QObject *parent = nullptr);
    virtual ~RepositoryManager();

    // Properties
    Q_PROPERTY(Environment currentEnvironment READ currentEnvironment
               WRITE setCurrentEnvironment NOTIFY environmentChanged)
    Q_PROPERTY(QJsonArray githubRepos READ githubRepos NOTIFY reposChanged)
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QString artifactBranchFilter READ artifactBranchFilter
               WRITE setArtifactBranchFilter NOTIFY artifactBranchFilterChanged)
    Q_PROPERTY(QStringList availableBranches READ availableBranches
               NOTIFY availableBranchesChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)

    // Getters
    Environment currentEnvironment() const { return _environment; }
    QJsonArray githubRepos() const;
    bool isLoading() const { return _isLoading; }
    QString errorMessage() const { return _errorMessage; }
    QString artifactBranchFilter() const { return _artifactBranchFilter; }
    QStringList availableBranches() const { return _availableBranches; }
    QString statusMessage() const { return _statusMessage; }

    /**
     * @brief Set the current CDN environment
     */
    Q_INVOKABLE void setCurrentEnvironment(Environment env);

    /**
     * @brief Get the CDN URL for the current environment
     */
    Q_INVOKABLE QUrl getCurrentCdnUrl() const;

    /**
     * @brief Get the CDN URL for a specific environment
     */
    Q_INVOKABLE QUrl getCdnUrl(Environment env) const;

    /**
     * @brief Get environment name for display
     */
    Q_INVOKABLE QString environmentName(Environment env) const;

    /**
     * @brief Get list of all environment names
     */
    Q_INVOKABLE QStringList environmentNames() const;

    /**
     * @brief Add a GitHub repository to track
     * @param owner Repository owner (organization or user)
     * @param repo Repository name
     * @param defaultBranch Default branch to use (default: "main")
     */
    Q_INVOKABLE void addGitHubRepo(const QString &owner, const QString &repo,
                                    const QString &defaultBranch = "main");

    /**
     * @brief Add a GitHub repository and fetch its default branch from GitHub
     * @param owner Repository owner (organization or user)
     * @param repo Repository name
     */
    Q_INVOKABLE void addGitHubRepoWithAutoDetect(const QString &owner, const QString &repo);

    /**
     * @brief Remove a GitHub repository
     */
    Q_INVOKABLE void removeGitHubRepo(const QString &owner, const QString &repo);

    /**
     * @brief Enable or disable a GitHub repository
     */
    Q_INVOKABLE void setRepoEnabled(const QString &owner, const QString &repo, bool enabled);

    /**
     * @brief Check if a repository is enabled
     */
    Q_INVOKABLE bool isRepoEnabled(const QString &owner, const QString &repo) const;

    /**
     * @brief Set the default branch for a repository
     */
    Q_INVOKABLE void setDefaultBranch(const QString &owner, const QString &repo,
                                       const QString &branch);

    /**
     * @brief Get the default branch for a repository
     */
    Q_INVOKABLE QString getDefaultBranch(const QString &owner, const QString &repo) const;

    /**
     * @brief Set the artifact branch filter and re-fetch artifacts from that branch
     * @param branch The branch to filter/fetch artifacts from (empty = use default branches)
     */
    Q_INVOKABLE void setArtifactBranchFilter(const QString &branch);

    /**
     * @brief Fetch available branches from all enabled repositories
     */
    Q_INVOKABLE void fetchAvailableBranches();

    /**
     * @brief Refresh all sources (CDN + enabled GitHub repos)
     */
    Q_INVOKABLE void refreshAllSources();

    /**
     * @brief Get merged OS list from all sources
     * @return Combined JSON array of all available images
     */
    Q_INVOKABLE QJsonArray getMergedOsList() const;

    /**
     * @brief Get images from CDN only
     */
    Q_INVOKABLE QJsonArray getCdnOsList() const;

    /**
     * @brief Get images from GitHub repos only
     */
    Q_INVOKABLE QJsonArray getGitHubOsList() const;

    /**
     * @brief Set the GitHub client for API access
     */
    void setGitHubClient(GitHubClient *client);

    /**
     * @brief Load settings from persistent storage
     */
    void loadSettings();

    /**
     * @brief Save settings to persistent storage
     */
    void saveSettings();

    /**
     * @brief Convert repository list to JSON for storage
     */
    QString reposToJson() const;

    /**
     * @brief Load repository list from JSON
     */
    void loadReposFromJson(const QString &json);

signals:
    void environmentChanged();
    void reposChanged();
    void loadingChanged();
    void errorMessageChanged();
    void artifactBranchFilterChanged();
    void availableBranchesChanged();
    void statusMessageChanged();
    void osListReady();
    void cdnListReady(const QJsonArray &list);
    void githubListReady(const QJsonArray &list);
    void refreshError(const QString &message);

private slots:
    void onCdnListReady(const QJsonArray &list);
    void onGitHubWicFilesReady(const QJsonArray &wicFiles);
    void onGitHubArtifactFilesReady(const QJsonArray &wicFiles);
    void onBranchesReady(const QJsonArray &branches);
    void onSourceError(const QString &message);

private:
    void setLoading(bool loading);
    void setError(const QString &message);
    void setStatusMessage(const QString &message);
    void checkRefreshComplete();

    struct GitHubRepoInfo {
        QString owner;
        QString repo;
        QString defaultBranch;
        bool enabled;
    };

    Environment _environment = Production;
    QVector<GitHubRepoInfo> _githubRepos;
    QJsonArray _cdnOsList;
    QJsonArray _githubOsList;

    GitHubClient *_githubClient = nullptr;
    LaerdalCdnSource *_cdnSource = nullptr;

    QSettings _settings;
    bool _isLoading = false;
    QString _errorMessage;
    QString _statusMessage;
    QString _artifactBranchFilter;
    QStringList _availableBranches;

    int _pendingRefreshCount = 0;
    int _pendingBranchFetchCount = 0;

    // Settings keys
    static constexpr const char* SETTINGS_ENVIRONMENT = "laerdal/environment";
    static constexpr const char* SETTINGS_GITHUB_REPOS = "laerdal/github_repos";
    static constexpr const char* SETTINGS_REPO_BRANCHES = "laerdal/repo_branches";
    static constexpr const char* SETTINGS_REPO_ENABLED = "laerdal/repo_enabled";
};

#endif // REPOSITORYMANAGER_H
