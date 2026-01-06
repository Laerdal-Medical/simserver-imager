/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "repositorymanager.h"
#include "laerdalcdnsource.h"
#include "../github/githubclient.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QSet>

RepositoryManager::RepositoryManager(QObject *parent)
    : QObject(parent)
{
    _cdnSource = new LaerdalCdnSource(this);

    connect(_cdnSource, &LaerdalCdnSource::listReady,
            this, &RepositoryManager::onCdnListReady);
    connect(_cdnSource, &LaerdalCdnSource::error,
            this, &RepositoryManager::onSourceError);
}

RepositoryManager::~RepositoryManager()
{
}

void RepositoryManager::setCurrentEnvironment(Environment env)
{
    if (_environment != env) {
        _environment = env;
        _settings.setValue(SETTINGS_ENVIRONMENT, static_cast<int>(env));
        _settings.sync();
        emit environmentChanged();

        qDebug() << "RepositoryManager: Environment changed to" << environmentName(env);
    }
}

QUrl RepositoryManager::getCurrentCdnUrl() const
{
    return getCdnUrl(_environment);
}

QUrl RepositoryManager::getCdnUrl(Environment env) const
{
    const QString base = "https://laerdalcdn.blob.core.windows.net/software";

    switch (env) {
    case Production:
        return QUrl(base + "/release/SimPad/factory-images/images.json");
    case Test:
    case Beta:
        return QUrl(base + "/test/SimPad/factory-images/images.json");
    case Dev:
        return QUrl(base + "/dev/SimPad/factory-images/images.json");
    case ReleaseCandidate:
        return QUrl(base + "/release-candidate/SimPad/factory-images/images.json");
    }

    return QUrl(base + "/release/SimPad/factory-images/images.json");
}

QString RepositoryManager::environmentName(Environment env) const
{
    switch (env) {
    case Production:
        return tr("Production");
    case Test:
        return tr("Test");
    case Dev:
        return tr("Development");
    case Beta:
        return tr("Beta");
    case ReleaseCandidate:
        return tr("Release Candidate");
    }
    return tr("Unknown");
}

QStringList RepositoryManager::environmentNames() const
{
    return {
        environmentName(Production),
        environmentName(Test),
        environmentName(Dev),
        environmentName(Beta),
        environmentName(ReleaseCandidate)
    };
}

QJsonArray RepositoryManager::githubRepos() const
{
    QJsonArray result;
    for (const auto &repo : _githubRepos) {
        QJsonObject obj;
        obj["owner"] = repo.owner;
        obj["repo"] = repo.repo;
        obj["defaultBranch"] = repo.defaultBranch;
        obj["enabled"] = repo.enabled;
        obj["fullName"] = QString("%1/%2").arg(repo.owner, repo.repo);
        result.append(obj);
    }
    return result;
}

void RepositoryManager::addGitHubRepo(const QString &owner, const QString &repo,
                                       const QString &defaultBranch)
{
    // Check if already exists
    for (const auto &existing : _githubRepos) {
        if (existing.owner == owner && existing.repo == repo) {
            qDebug() << "RepositoryManager: Repo already exists:" << owner << "/" << repo;
            return;
        }
    }

    GitHubRepoInfo info;
    info.owner = owner;
    info.repo = repo;
    info.defaultBranch = defaultBranch;
    info.enabled = true;

    _githubRepos.append(info);
    saveSettings();
    emit reposChanged();

    qDebug() << "RepositoryManager: Added repo:" << owner << "/" << repo;

    // Trigger a refresh to fetch CI images from the new repo
    refreshAllSources();
}

void RepositoryManager::addGitHubRepoWithAutoDetect(const QString &owner, const QString &repo)
{
    // Check if already exists
    for (const auto &existing : _githubRepos) {
        if (existing.owner == owner && existing.repo == repo) {
            qDebug() << "RepositoryManager: Repo already exists:" << owner << "/" << repo;
            return;
        }
    }

    // Fetch repo info to get default branch
    if (_githubClient) {
        // Connect to receive the repo info (one-shot connection)
        QMetaObject::Connection *conn = new QMetaObject::Connection;
        *conn = connect(_githubClient, &GitHubClient::repoInfoReady, this,
            [this, owner, repo, conn](const QString &rOwner, const QString &rRepo, const QString &defaultBranch) {
                if (rOwner == owner && rRepo == repo) {
                    // Disconnect this one-shot handler
                    disconnect(*conn);
                    delete conn;

                    // Now add the repo with the detected default branch
                    addGitHubRepo(owner, repo, defaultBranch);
                    qDebug() << "RepositoryManager: Auto-detected default branch for"
                             << owner << "/" << repo << ":" << defaultBranch;
                }
            });

        // Also handle errors
        QMetaObject::Connection *errConn = new QMetaObject::Connection;
        *errConn = connect(_githubClient, &GitHubClient::error, this,
            [this, owner, repo, conn, errConn](const QString &message) {
                // Disconnect handlers
                disconnect(*conn);
                disconnect(*errConn);
                delete conn;
                delete errConn;

                // Fall back to "main" on error
                qDebug() << "RepositoryManager: Failed to fetch repo info for"
                         << owner << "/" << repo << ":" << message
                         << "- using 'main' as default";
                addGitHubRepo(owner, repo, "main");
            });

        _githubClient->fetchRepoInfo(owner, repo);
    } else {
        // No GitHub client, fall back to "main"
        addGitHubRepo(owner, repo, "main");
    }
}

void RepositoryManager::removeGitHubRepo(const QString &owner, const QString &repo)
{
    for (int i = 0; i < _githubRepos.size(); ++i) {
        if (_githubRepos[i].owner == owner && _githubRepos[i].repo == repo) {
            _githubRepos.removeAt(i);
            saveSettings();
            emit reposChanged();
            qDebug() << "RepositoryManager: Removed repo:" << owner << "/" << repo;
            return;
        }
    }
}

void RepositoryManager::setRepoEnabled(const QString &owner, const QString &repo, bool enabled)
{
    for (auto &info : _githubRepos) {
        if (info.owner == owner && info.repo == repo) {
            if (info.enabled != enabled) {
                info.enabled = enabled;
                saveSettings();
                emit reposChanged();
                qDebug() << "RepositoryManager: Repo" << owner << "/" << repo
                         << "enabled:" << enabled;
            }
            return;
        }
    }
}

bool RepositoryManager::isRepoEnabled(const QString &owner, const QString &repo) const
{
    for (const auto &info : _githubRepos) {
        if (info.owner == owner && info.repo == repo) {
            return info.enabled;
        }
    }
    return false;
}

void RepositoryManager::setDefaultBranch(const QString &owner, const QString &repo,
                                          const QString &branch)
{
    for (auto &info : _githubRepos) {
        if (info.owner == owner && info.repo == repo) {
            info.defaultBranch = branch;
            saveSettings();
            return;
        }
    }
}

QString RepositoryManager::getDefaultBranch(const QString &owner, const QString &repo) const
{
    for (const auto &info : _githubRepos) {
        if (info.owner == owner && info.repo == repo) {
            return info.defaultBranch;
        }
    }
    return "main";
}

void RepositoryManager::setArtifactBranchFilter(const QString &branch)
{
    if (_artifactBranchFilter != branch) {
        _artifactBranchFilter = branch;
        emit artifactBranchFilterChanged();
        qDebug() << "RepositoryManager: Artifact branch filter set to:" << branch;

        // Re-fetch artifacts from the new branch
        if (_githubClient) {
            // Clear existing GitHub artifacts (keep releases)
            QJsonArray releasesOnly;
            for (const auto &item : _githubOsList) {
                QJsonObject obj = item.toObject();
                if (obj["source_type"].toString() == "release") {
                    releasesOnly.append(item);
                }
            }
            _githubOsList = releasesOnly;

            // Re-fetch artifacts with new branch
            _pendingRefreshCount = 0;
            for (const auto &repo : _githubRepos) {
                if (repo.enabled) {
                    _pendingRefreshCount++;
                    QString branchToFetch = branch.isEmpty() ? repo.defaultBranch : branch;
                    _githubClient->searchWicFilesInArtifacts(repo.owner, repo.repo, branchToFetch);
                }
            }

            if (_pendingRefreshCount > 0) {
                setLoading(true);
                qDebug() << "RepositoryManager: Branch filter refresh started, pending:" << _pendingRefreshCount;
            } else {
                // No enabled repos, complete immediately
                setLoading(false);
                emit osListReady();
            }
        }
    }
}

void RepositoryManager::fetchAvailableBranches()
{
    if (!_githubClient) {
        qWarning() << "RepositoryManager: No GitHub client available for fetching branches";
        return;
    }

    _availableBranches.clear();
    _pendingBranchFetchCount = 0;

    for (const auto &repo : _githubRepos) {
        if (repo.enabled) {
            _pendingBranchFetchCount++;
            _githubClient->fetchBranches(repo.owner, repo.repo);
        }
    }

    qDebug() << "RepositoryManager: Fetching branches from" << _pendingBranchFetchCount << "repos";
}

void RepositoryManager::refreshAllSources()
{
    setLoading(true);
    setError(QString());

    _cdnOsList = QJsonArray();
    _githubOsList = QJsonArray();
    _pendingRefreshCount = 1; // CDN source

    // Count enabled GitHub repos (releases + artifacts = 2 requests per repo)
    for (const auto &repo : _githubRepos) {
        if (repo.enabled && _githubClient) {
            _pendingRefreshCount += 2; // Both releases and artifacts
        }
    }

    qDebug() << "RepositoryManager: Starting refresh, pending:" << _pendingRefreshCount;

    // Fetch CDN list
    _cdnSource->fetchList(getCurrentCdnUrl());

    // Fetch GitHub releases and artifacts for enabled repos
    if (_githubClient) {
        for (const auto &repo : _githubRepos) {
            if (repo.enabled) {
                // Search releases
                _githubClient->searchWicFilesInReleases(repo.owner, repo.repo);
                // Search artifacts (from workflow runs) - use filter branch if set, else default
                QString branchToFetch = _artifactBranchFilter.isEmpty() ? repo.defaultBranch : _artifactBranchFilter;
                _githubClient->searchWicFilesInArtifacts(repo.owner, repo.repo, branchToFetch);
            }
        }

        // Also fetch available branches for the dropdown
        fetchAvailableBranches();
    }
}

QJsonArray RepositoryManager::getMergedOsList() const
{
    QJsonArray merged;

    // Add CDN items first
    for (const auto &item : _cdnOsList) {
        merged.append(item);
    }

    // Add GitHub items (filtered by branch if applicable)
    QJsonArray githubItems = getGitHubOsList();
    for (const auto &item : githubItems) {
        merged.append(item);
    }

    return merged;
}

QJsonArray RepositoryManager::getCdnOsList() const
{
    return _cdnOsList;
}

QJsonArray RepositoryManager::getGitHubOsList() const
{
    // Return all GitHub items (filtering is done at fetch time via setArtifactBranchFilter)
    return _githubOsList;
}

void RepositoryManager::setGitHubClient(GitHubClient *client)
{
    if (_githubClient) {
        disconnect(_githubClient, nullptr, this, nullptr);
    }

    _githubClient = client;

    if (_githubClient) {
        connect(_githubClient, &GitHubClient::wicFilesReady,
                this, &RepositoryManager::onGitHubWicFilesReady);
        connect(_githubClient, &GitHubClient::artifactWicFilesReady,
                this, &RepositoryManager::onGitHubArtifactFilesReady);
        connect(_githubClient, &GitHubClient::branchesReady,
                this, &RepositoryManager::onBranchesReady);
        connect(_githubClient, &GitHubClient::error,
                this, &RepositoryManager::onSourceError);
    }
}

void RepositoryManager::loadSettings()
{
    // Load environment
    int envInt = _settings.value(SETTINGS_ENVIRONMENT, static_cast<int>(Production)).toInt();
    _environment = static_cast<Environment>(envInt);

    // Load repos from JSON
    QString reposJson = _settings.value(SETTINGS_GITHUB_REPOS).toString();
    if (!reposJson.isEmpty()) {
        loadReposFromJson(reposJson);
    }

    // Load enabled states
    QVariantMap enabledMap = _settings.value(SETTINGS_REPO_ENABLED).toMap();
    for (auto &repo : _githubRepos) {
        QString key = QString("%1/%2").arg(repo.owner, repo.repo);
        if (enabledMap.contains(key)) {
            repo.enabled = enabledMap[key].toBool();
        }
    }

    // Load branches
    QVariantMap branchMap = _settings.value(SETTINGS_REPO_BRANCHES).toMap();
    for (auto &repo : _githubRepos) {
        QString key = QString("%1/%2").arg(repo.owner, repo.repo);
        if (branchMap.contains(key)) {
            repo.defaultBranch = branchMap[key].toString();
        }
    }

    qDebug() << "RepositoryManager: Loaded settings, environment:"
             << environmentName(_environment)
             << ", repos:" << _githubRepos.size();
}

void RepositoryManager::saveSettings()
{
    _settings.setValue(SETTINGS_ENVIRONMENT, static_cast<int>(_environment));
    _settings.setValue(SETTINGS_GITHUB_REPOS, reposToJson());

    // Save enabled states
    QVariantMap enabledMap;
    for (const auto &repo : _githubRepos) {
        QString key = QString("%1/%2").arg(repo.owner, repo.repo);
        enabledMap[key] = repo.enabled;
    }
    _settings.setValue(SETTINGS_REPO_ENABLED, enabledMap);

    // Save branches
    QVariantMap branchMap;
    for (const auto &repo : _githubRepos) {
        QString key = QString("%1/%2").arg(repo.owner, repo.repo);
        branchMap[key] = repo.defaultBranch;
    }
    _settings.setValue(SETTINGS_REPO_BRANCHES, branchMap);

    _settings.sync();
}

QString RepositoryManager::reposToJson() const
{
    QJsonArray arr;
    for (const auto &repo : _githubRepos) {
        QJsonObject obj;
        obj["owner"] = repo.owner;
        obj["repo"] = repo.repo;
        obj["defaultBranch"] = repo.defaultBranch;
        arr.append(obj);
    }
    return QJsonDocument(arr).toJson(QJsonDocument::Compact);
}

void RepositoryManager::loadReposFromJson(const QString &json)
{
    _githubRepos.clear();

    QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isArray()) {
        qWarning() << "RepositoryManager: Invalid repos JSON";
        return;
    }

    for (const auto &item : doc.array()) {
        QJsonObject obj = item.toObject();
        GitHubRepoInfo info;
        info.owner = obj["owner"].toString();
        info.repo = obj["repo"].toString();
        info.defaultBranch = obj["defaultBranch"].toString("main");
        info.enabled = true; // Will be overridden by enabled settings

        if (!info.owner.isEmpty() && !info.repo.isEmpty()) {
            _githubRepos.append(info);
        }
    }

    emit reposChanged();
}

void RepositoryManager::onCdnListReady(const QJsonArray &list)
{
    _cdnOsList = list;
    emit cdnListReady(list);

    qDebug() << "RepositoryManager: CDN list ready with" << list.size() << "items";

    _pendingRefreshCount--;
    checkRefreshComplete();
}

void RepositoryManager::onGitHubWicFilesReady(const QJsonArray &wicFiles)
{
    // Convert WIC files to OS list format and append
    for (const auto &wicValue : wicFiles) {
        QJsonObject wic = wicValue.toObject();

        QJsonObject osEntry;
        osEntry["name"] = wic["name"].toString();
        osEntry["description"] = QString("%1/%2 - Release: %3").arg(wic["owner"].toString(), wic["repo"].toString(), wic["release_name"].toString());
        osEntry["url"] = wic["download_url"].toString();
        osEntry["extract_size"] = wic["size"].toVariant().toLongLong();
        osEntry["image_download_size"] = wic["size"].toVariant().toLongLong();
        osEntry["release_date"] = wic["published_at"].toString();
        osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/use_custom.png";
        osEntry["init_format"] = "none";
        osEntry["source"] = "github";
        osEntry["source_type"] = "release";
        osEntry["prerelease"] = wic["prerelease"].toBool();

        _githubOsList.append(osEntry);
    }

    qDebug() << "RepositoryManager: GitHub WIC files added:" << wicFiles.size();

    _pendingRefreshCount--;
    checkRefreshComplete();
}

void RepositoryManager::onGitHubArtifactFilesReady(const QJsonArray &wicFiles)
{
    // Convert artifact WIC files to OS list format and append
    for (const auto &wicValue : wicFiles) {
        QJsonObject wic = wicValue.toObject();
        QString artifactName = wic["name"].toString();

        QJsonObject osEntry;
        osEntry["name"] = artifactName;
        osEntry["description"] = QString("%1/%2 - Branch: %3").arg(wic["owner"].toString(), wic["repo"].toString(), wic["branch"].toString());
        osEntry["url"] = wic["download_url"].toString();
        osEntry["extract_size"] = wic["size"].toVariant().toLongLong();
        osEntry["image_download_size"] = wic["size"].toVariant().toLongLong();
        osEntry["release_date"] = wic["created_at"].toString();
        osEntry["init_format"] = "none";
        osEntry["source"] = "github";
        osEntry["source_type"] = "artifact";
        osEntry["artifact_id"] = wic["artifact_id"].toVariant().toLongLong();
        osEntry["run_id"] = wic["run_id"].toVariant().toLongLong();
        osEntry["branch"] = wic["branch"].toString();
        osEntry["source_owner"] = wic["owner"].toString();
        osEntry["source_repo_name"] = wic["repo"].toString();

        // Set devices array and icon based on artifact name
        // SimPad: imx6 = SimPad Plus, imx8 = SimPad Plus 2
        // SimMan: simman3g-64 = 64-bit, simman3g-32 = 32-bit
        QJsonArray devices;
        QString artifactNameLower = artifactName.toLower();

        if (artifactNameLower.contains("simman3g-64") || artifactNameLower.contains("simman-64")) {
            devices.append("simman3g-64");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
        } else if (artifactNameLower.contains("simman3g-32") || artifactNameLower.contains("simman-32")) {
            devices.append("simman3g-32");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
        } else if (artifactNameLower.contains("imx8")) {
            devices.append("imx8");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simpad_plus2.png";
        } else if (artifactNameLower.contains("imx6")) {
            devices.append("imx6");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simpad_plus.png";
        } else {
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/use_custom.png";
        }
        osEntry["devices"] = devices;

        _githubOsList.append(osEntry);
    }

    qDebug() << "RepositoryManager: GitHub artifact WIC files added:" << wicFiles.size()
             << ", pending before decrement:" << _pendingRefreshCount;

    _pendingRefreshCount--;
    checkRefreshComplete();
}

void RepositoryManager::onBranchesReady(const QJsonArray &branches)
{
    // Add branches to the available list (deduplicating)
    QSet<QString> branchSet(_availableBranches.begin(), _availableBranches.end());

    for (const auto &branchValue : branches) {
        // GitHubClient emits branch names as strings directly, not as objects
        QString branchName = branchValue.toString();
        if (!branchName.isEmpty()) {
            branchSet.insert(branchName);
        }
    }

    _pendingBranchFetchCount--;

    if (_pendingBranchFetchCount <= 0) {
        _pendingBranchFetchCount = 0;
        _availableBranches = branchSet.values();
        _availableBranches.sort();

        qDebug() << "RepositoryManager: Available branches:" << _availableBranches;
        emit availableBranchesChanged();
    }
}

void RepositoryManager::onSourceError(const QString &message)
{
    qWarning() << "RepositoryManager: Source error:" << message;

    _pendingRefreshCount--;
    checkRefreshComplete();

    emit refreshError(message);
}

void RepositoryManager::setLoading(bool loading)
{
    if (_isLoading != loading) {
        _isLoading = loading;
        emit loadingChanged();
    }
}

void RepositoryManager::setError(const QString &message)
{
    if (_errorMessage != message) {
        _errorMessage = message;
        emit errorMessageChanged();
    }
}

void RepositoryManager::setStatusMessage(const QString &message)
{
    if (_statusMessage != message) {
        _statusMessage = message;
        emit statusMessageChanged();
    }
}

void RepositoryManager::checkRefreshComplete()
{
    if (_pendingRefreshCount <= 0) {
        _pendingRefreshCount = 0;
        setLoading(false);
        emit osListReady();
        emit githubListReady(_githubOsList);

        // Set status message based on results
        int githubCount = _githubOsList.size();
        if (githubCount == 0) {
            // Check if there are any enabled repos
            bool hasEnabledRepos = false;
            for (const auto &repo : _githubRepos) {
                if (repo.enabled) {
                    hasEnabledRepos = true;
                    break;
                }
            }
            if (hasEnabledRepos) {
                setStatusMessage(tr("No CI builds found for selected repositories"));
            } else {
                setStatusMessage(tr("No GitHub repositories enabled"));
            }
        } else {
            setStatusMessage(tr("%1 CI build(s) found").arg(githubCount));
        }

        qDebug() << "RepositoryManager: Refresh complete, total items:"
                 << getMergedOsList().size();
    }
}

void RepositoryManager::inspectArtifact(qint64 artifactId, const QString &artifactName,
                                         const QString &owner, const QString &repo,
                                         const QString &branch)
{
    if (!_githubClient) {
        emit refreshError(tr("GitHub client not configured"));
        return;
    }

    qDebug() << "RepositoryManager: Requesting artifact inspection for" << artifactName
             << "id:" << artifactId;

    setStatusMessage(tr("Downloading artifact to inspect contents..."));
    setLoading(true);

    // Connect to the artifact contents ready signal (single-shot)
    connect(_githubClient, &GitHubClient::artifactContentsReady, this,
            [this](qint64 id, const QString &name, const QString &own, const QString &rep,
                   const QString &br, const QJsonArray &wicFiles, const QString &zipPath) {
                setLoading(false);
                setStatusMessage(tr("Found %1 installable file(s) in artifact").arg(wicFiles.size()));
                emit artifactContentsReady(id, name, own, rep, br, wicFiles, zipPath);
            }, Qt::SingleShotConnection);

    connect(_githubClient, &GitHubClient::error, this,
            [this](const QString &message) {
                setLoading(false);
                setStatusMessage(tr("Failed to inspect artifact"));
                emit refreshError(message);
            }, Qt::SingleShotConnection);

    connect(_githubClient, &GitHubClient::artifactDownloadProgress, this,
            [this](qint64 bytesReceived, qint64 bytesTotal) {
                if (bytesTotal > 0) {
                    int percent = static_cast<int>((bytesReceived * 100) / bytesTotal);
                    setStatusMessage(tr("Downloading artifact... %1%").arg(percent));
                }
                emit artifactDownloadProgress(bytesReceived, bytesTotal);
            });

    _githubClient->inspectArtifactContents(owner, repo, artifactId, artifactName, branch);
}

void RepositoryManager::cancelArtifactInspection()
{
    if (_githubClient) {
        qDebug() << "RepositoryManager: Cancelling artifact inspection";
        _githubClient->cancelArtifactInspection();
        setLoading(false);
        setStatusMessage(tr("Download cancelled"));
        emit artifactInspectionCancelled();
    }
}
