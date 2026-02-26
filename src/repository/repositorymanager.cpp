/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "repositorymanager.h"
#include "laerdalcdnsource.h"
#include "../github/githubclient.h"
#include "../devicedetection.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QSet>
#include <QTimer>
#include <QRegularExpression>

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
        _settings.setValue(SETTINGS_ARTIFACT_BRANCH_FILTER, branch);
        _settings.sync();
        emit artifactBranchFilterChanged();
        qDebug() << "RepositoryManager: Artifact branch filter set to:" << branch;

        // Handle filter change - only relevant for github-ci source type
        if (_githubClient && _selectedSourceType == "github-ci") {
            // Clear existing GitHub artifacts (keep releases in storage)
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

void RepositoryManager::setSelectedSourceType(const QString &sourceType)
{
    if (_selectedSourceType != sourceType) {
        _selectedSourceType = sourceType;
        _settings.setValue(SETTINGS_SOURCE_TYPE, sourceType);
        emit selectedSourceTypeChanged();

        // When switching to a GitHub source type, fetch branches
        // CI images will be fetched when user clicks Next on the Source Selection step
        if ((sourceType == "github-releases" || sourceType == "github-ci") && _githubClient) {
            qDebug() << "RepositoryManager: Source type set to" << sourceType << ", fetching branches...";
            fetchAvailableBranches();
        }

        // Notify that the OS list source has changed - this triggers the UI to reload
        // and call setFilteredImageCount() with the correct filtered count
        emit osListReady();
        qDebug() << "RepositoryManager: Source type set to:" << sourceType;
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
            _pendingBranchFetchCount += 2; // branches + tags
            _githubClient->fetchBranches(repo.owner, repo.repo);
            _githubClient->fetchTags(repo.owner, repo.repo);
        }
    }

    qDebug() << "RepositoryManager: Fetching branches and tags from" << (_pendingBranchFetchCount / 2) << "repos";

    // Set a timeout to ensure branches eventually get emitted even if some requests fail
    // This prevents the UI from hanging indefinitely if network requests fail silently
    if (_pendingBranchFetchCount > 0) {
        QTimer::singleShot(15000, this, [this]() {
            if (_pendingBranchFetchCount > 0) {
                qWarning() << "RepositoryManager: Branch fetch timeout, emitting partial results. Pending:" << _pendingBranchFetchCount;
                _pendingBranchFetchCount = 0;
                _availableBranches.sort();
                emit availableBranchesChanged();
            }
        });
    }
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

    // Filter based on selected source type
    if (_selectedSourceType == "cdn") {
        // CDN only
        for (const auto &item : _cdnOsList) {
            merged.append(item);
        }
    } else if (_selectedSourceType == "github-releases" || _selectedSourceType == "github-ci") {
        // GitHub (filtered by source type and optionally by branch)
        QJsonArray githubItems = getGitHubOsList();
        for (const auto &item : githubItems) {
            merged.append(item);
        }
    } else {
        // Default: show CDN (fallback)
        for (const auto &item : _cdnOsList) {
            merged.append(item);
        }
    }

    return merged;
}

QJsonArray RepositoryManager::getCdnOsList() const
{
    return _cdnOsList;
}

QJsonArray RepositoryManager::getGitHubOsList() const
{
    // Filter based on selected source type:
    // - "github-releases": show only releases
    // - "github-ci": show only CI artifacts, optionally filtered by branch
    QJsonArray filtered;

    if (_selectedSourceType == "github-releases") {
        // Releases only
        for (const auto &item : _githubOsList) {
            QJsonObject obj = item.toObject();
            if (obj["source_type"].toString() == "release") {
                filtered.append(item);
            }
        }
    } else if (_selectedSourceType == "github-ci") {
        // CI artifacts only, optionally filtered by branch
        for (const auto &item : _githubOsList) {
            QJsonObject obj = item.toObject();
            if (obj["source_type"].toString() == "artifact") {
                if (_artifactBranchFilter.isEmpty()) {
                    filtered.append(item);
                } else {
                    QString artifactBranch = obj["branch"].toString();
                    if (artifactBranch == _artifactBranchFilter) {
                        filtered.append(item);
                    }
                }
            }
        }
    } else {
        // Fallback: return all GitHub items
        filtered = _githubOsList;
    }

    // Sort by release_date descending (newest first)
    QList<QJsonValue> sortedList;
    for (const auto &item : filtered) {
        sortedList.append(item);
    }

    std::sort(sortedList.begin(), sortedList.end(), [](const QJsonValue &a, const QJsonValue &b) {
        QString dateA = a.toObject()["release_date"].toString();
        QString dateB = b.toObject()["release_date"].toString();
        // ISO 8601 dates can be compared lexicographically
        return dateA > dateB;  // Descending order (newest first)
    });

    QJsonArray sorted;
    for (const auto &item : sortedList) {
        sorted.append(item);
    }

    return sorted;
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
        connect(_githubClient, &GitHubClient::tagsReady,
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

    // Load source type
    _selectedSourceType = _settings.value(SETTINGS_SOURCE_TYPE, "cdn").toString();

    // Load artifact branch filter (last used branch selection)
    _artifactBranchFilter = _settings.value(SETTINGS_ARTIFACT_BRANCH_FILTER).toString();

    // Migrate old "github" source type to new values
    if (_selectedSourceType == "github") {
        if (_artifactBranchFilter == "RELEASES_ONLY") {
            _selectedSourceType = "github-releases";
            _artifactBranchFilter = "";
            _settings.setValue(SETTINGS_ARTIFACT_BRANCH_FILTER, "");
        } else {
            _selectedSourceType = "github-ci";
        }
        _settings.setValue(SETTINGS_SOURCE_TYPE, _selectedSourceType);
        _settings.sync();
        qDebug() << "RepositoryManager: Migrated source type 'github' to" << _selectedSourceType;
    }

    // Clear any lingering "RELEASES_ONLY" filter value
    if (_artifactBranchFilter == "RELEASES_ONLY") {
        _artifactBranchFilter = "";
        _settings.setValue(SETTINGS_ARTIFACT_BRANCH_FILTER, "");
        _settings.sync();
    }

    qDebug() << "RepositoryManager: Loaded settings, environment:"
             << environmentName(_environment)
             << ", repos:" << _githubRepos.size()
             << ", source type:" << _selectedSourceType
             << ", branch filter:" << _artifactBranchFilter;
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

void RepositoryManager::onGitHubWicFilesReady(const QJsonArray &releaseGroups)
{
    // Convert release groups to OS list format (one entry per release)
    for (const auto &releaseValue : releaseGroups) {
        QJsonObject release = releaseValue.toObject();
        QString releaseName = release["release_name"].toString();
        QString tag = release["tag"].toString();
        QString owner = release["owner"].toString();
        QString repo = release["repo"].toString();
        QJsonArray assets = release["assets"].toArray();

        // Get version from release name or tag
        QString version = extractVersion(releaseName);
        if (version.isEmpty()) version = extractVersion(tag);

        // Get device name from release name or tag (releases can be device-specific)
        QString deviceName = extractDeviceName(releaseName);
        if (deviceName.isEmpty()) deviceName = extractDeviceName(tag);

        // Determine compatible devices and icon from assets
        QSet<QString> deviceSet;
        QString icon = DeviceDetection::getIconPath(DeviceDetection::DeviceType::Unknown);

        for (const auto &assetValue : assets) {
            QJsonObject asset = assetValue.toObject();
            QString assetName = asset["name"].toString();
            bool isVsi = assetName.toLower().endsWith(".vsi");

            auto type = DeviceDetection::detectFromFilename(assetName);
            if (type != DeviceDetection::DeviceType::Unknown) {
                QJsonArray devTags = DeviceDetection::getDeviceTags(type, isVsi);
                for (const auto &t : devTags)
                    deviceSet.insert(t.toString());
                if (icon.contains("use_custom"))
                    icon = DeviceDetection::getIconPath(type);
            }
        }

        // Fall back to release name/tag for device detection when
        // asset filenames don't contain device identifiers
        if (deviceSet.isEmpty()) {
            auto type = DeviceDetection::detectFromFilename(releaseName);
            if (type == DeviceDetection::DeviceType::Unknown)
                type = DeviceDetection::detectFromFilename(tag);
            if (type != DeviceDetection::DeviceType::Unknown) {
                QJsonArray devTags = DeviceDetection::getDeviceTags(type, false);
                for (const auto &t : devTags)
                    deviceSet.insert(t.toString());
                icon = DeviceDetection::getIconPath(type);
            }
        }

        QJsonArray devices;
        for (const QString &dev : deviceSet) {
            devices.append(dev);
        }

        QJsonObject osEntry;
        osEntry["name"] = buildDisplayName(deviceName, version, releaseName);
        osEntry["description"] = QString("%1/%2 - Release: %3").arg(owner, repo, releaseName);
        osEntry["release_date"] = release["published_at"].toString();
        osEntry["icon"] = icon;
        osEntry["init_format"] = "none";
        osEntry["source"] = "github";
        osEntry["source_type"] = "release";
        osEntry["prerelease"] = release["prerelease"].toBool();
        osEntry["source_owner"] = owner;
        osEntry["source_repo_name"] = repo;
        osEntry["release_tag"] = tag;
        osEntry["release_assets"] = assets;
        osEntry["devices"] = devices;

        // Set URL to a placeholder (actual download uses asset selection)
        osEntry["url"] = QString("github-release://%1/%2/releases/tag/%3").arg(owner, repo, tag);

        _githubOsList.append(osEntry);
    }

    qDebug() << "RepositoryManager: GitHub release groups added:" << releaseGroups.size();

    _pendingRefreshCount--;
    checkRefreshComplete();
}

void RepositoryManager::onGitHubArtifactFilesReady(const QJsonArray &wicFiles)
{
    // Convert artifact WIC files to OS list format and append
    for (const auto &wicValue : wicFiles) {
        QJsonObject wic = wicValue.toObject();
        QString artifactName = wic["name"].toString();
        QString artifactNameLower = artifactName.toLower();
        bool isVsi = artifactNameLower.endsWith(".vsi");

        QString deviceName = extractDeviceName(artifactName);
        QString version = extractVersion(artifactName);

        QJsonObject osEntry;
        osEntry["name"] = buildDisplayName(deviceName, version, artifactName);
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
        auto deviceType = DeviceDetection::detectFromFilename(artifactName);
        osEntry["devices"] = DeviceDetection::getDeviceTags(deviceType, isVsi);
        osEntry["icon"] = DeviceDetection::getIconPath(deviceType);

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

    // Save accumulated branches after each response (not just at the end)
    _availableBranches = branchSet.values();

    _pendingBranchFetchCount--;

    if (_pendingBranchFetchCount <= 0) {
        _pendingBranchFetchCount = 0;
        _availableBranches.sort();

        qDebug() << "RepositoryManager: Available branches:" << _availableBranches;
        emit availableBranchesChanged();
    }
}

void RepositoryManager::onBranchFetchError(const QString &message)
{
    // Handle errors during branch fetch - decrement counter to avoid UI hang
    qWarning() << "RepositoryManager: Branch fetch error:" << message;

    _pendingBranchFetchCount--;

    if (_pendingBranchFetchCount <= 0) {
        _pendingBranchFetchCount = 0;
        // Emit with whatever branches we did manage to fetch
        if (!_availableBranches.isEmpty()) {
            _availableBranches.sort();
        }
        qDebug() << "RepositoryManager: Branch fetch completed with errors, available:" << _availableBranches;
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

        // Note: Status message is set by setFilteredImageCount() which is called
        // from ImageWriter::getFilteredOSlistDocument() when the OS list model reloads.
        // This happens through the osListReady -> osListPrepared signal chain.

        qDebug() << "RepositoryManager: Refresh complete, total items:"
                 << getMergedOsList().size();
    }
}

QString RepositoryManager::extractDeviceName(const QString &text)
{
    return DeviceDetection::getDisplayName(DeviceDetection::detectFromFilename(text));
}

QString RepositoryManager::extractVersion(const QString &text)
{
    // Match version with optional pre-release suffix (e.g., 9.3.0, 9.3.0.1, 9.3.0-alpha, 9.3.0-rc1)
    static QRegularExpression versionRegex(QStringLiteral(R"(v?(\d+\.\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z0-9.]+)?))"));
    QRegularExpressionMatch match = versionRegex.match(text);
    return match.hasMatch() ? match.captured(1) : QString();
}

QString RepositoryManager::buildDisplayName(const QString &deviceName, const QString &version,
                                            const QString &fallback)
{
    if (!deviceName.isEmpty() && !version.isEmpty()) {
        return QStringLiteral("%1 v%2").arg(deviceName, version);
    }
    if (!deviceName.isEmpty()) {
        return deviceName;
    }
    if (!version.isEmpty()) {
        return QStringLiteral("v%1").arg(version);
    }
    return fallback;
}

void RepositoryManager::updateStatusMessage()
{
    if (_selectedSourceType == "cdn") {
        // CDN selected - clear the status message (CDN doesn't need a count banner)
        setStatusMessage(QString());
    } else if (_selectedSourceType == "github-releases") {
        // GitHub releases selected - show release count
        int releaseCount = 0;
        for (const auto &item : _githubOsList) {
            if (item.toObject()["source_type"].toString() == "release") {
                releaseCount++;
            }
        }
        if (releaseCount == 0) {
            bool hasEnabledRepos = false;
            for (const auto &repo : _githubRepos) {
                if (repo.enabled) {
                    hasEnabledRepos = true;
                    break;
                }
            }
            if (hasEnabledRepos) {
                setStatusMessage(tr("No releases found for selected repositories"));
            } else {
                setStatusMessage(tr("No GitHub repositories enabled"));
            }
        } else {
            setStatusMessage(tr("%1 release(s) available").arg(releaseCount));
        }
    } else if (_selectedSourceType == "github-ci") {
        // GitHub CI artifacts selected - show artifact count
        int artifactCount = 0;
        for (const auto &item : _githubOsList) {
            if (item.toObject()["source_type"].toString() == "artifact") {
                artifactCount++;
            }
        }
        if (artifactCount == 0) {
            bool hasEnabledRepos = false;
            for (const auto &repo : _githubRepos) {
                if (repo.enabled) {
                    hasEnabledRepos = true;
                    break;
                }
            }
            if (hasEnabledRepos) {
                setStatusMessage(tr("No CI artifacts found for selected repositories"));
            } else {
                setStatusMessage(tr("No GitHub repositories enabled"));
            }
        } else {
            setStatusMessage(tr("%1 CI artifact(s) available").arg(artifactCount));
        }
    }
}

void RepositoryManager::setFilteredImageCount(int filteredCount, int totalCount)
{
    if (_selectedSourceType == "cdn") {
        // CDN source
        if (filteredCount == 0 && totalCount == 0) {
            setStatusMessage(tr("No CDN images available"));
        } else if (filteredCount == totalCount) {
            setStatusMessage(tr("%1 CDN image(s) available").arg(totalCount));
        } else {
            setStatusMessage(tr("%1 CDN images available, %2 for this device").arg(totalCount).arg(filteredCount));
        }
    } else if (_selectedSourceType == "github-releases") {
        // GitHub releases
        if (filteredCount == 0 && totalCount == 0) {
            bool hasEnabledRepos = false;
            for (const auto &repo : _githubRepos) {
                if (repo.enabled) {
                    hasEnabledRepos = true;
                    break;
                }
            }
            if (hasEnabledRepos) {
                setStatusMessage(tr("No releases found for selected repositories"));
            } else {
                setStatusMessage(tr("No GitHub repositories enabled"));
            }
        } else if (filteredCount == totalCount) {
            setStatusMessage(tr("%1 release(s) available").arg(totalCount));
        } else {
            setStatusMessage(tr("%1 releases available, %2 for this device").arg(totalCount).arg(filteredCount));
        }
    } else if (_selectedSourceType == "github-ci") {
        // GitHub CI artifacts
        if (filteredCount == 0 && totalCount == 0) {
            bool hasEnabledRepos = false;
            for (const auto &repo : _githubRepos) {
                if (repo.enabled) {
                    hasEnabledRepos = true;
                    break;
                }
            }
            if (hasEnabledRepos) {
                setStatusMessage(tr("No CI artifacts found for selected repositories"));
            } else {
                setStatusMessage(tr("No GitHub repositories enabled"));
            }
        } else if (filteredCount == totalCount) {
            setStatusMessage(tr("%1 CI artifact(s) available").arg(totalCount));
        } else {
            setStatusMessage(tr("%1 CI artifacts available, %2 for this device").arg(totalCount).arg(filteredCount));
        }
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

bool RepositoryManager::isFileCompatibleWithDevice(const QString &filename,
                                                    const QString &deviceTag) const
{
    return DeviceDetection::isFileCompatibleWithDevice(filename, deviceTag);
}

void RepositoryManager::inspectSpuArtifact(qint64 artifactId, const QString &artifactName,
                                            const QString &owner, const QString &repo,
                                            const QString &branch)
{
    if (!_githubClient) {
        qWarning() << "RepositoryManager: Cannot inspect SPU artifact - no GitHub client";
        return;
    }

    qDebug() << "RepositoryManager: Inspecting SPU artifact" << artifactName
             << "from" << owner << "/" << repo << "branch:" << branch;

    setLoading(true);
    setStatusMessage(tr("Downloading artifact to inspect for SPU files..."));

    // Connect to receive the SPU contents
    connect(_githubClient, &GitHubClient::artifactSpuContentsReady, this,
            [this, artifactId, artifactName, owner, repo, branch]
            (qint64 id, const QString &name, const QString &own, const QString &rep,
             const QString &br, const QJsonArray &spuFiles, const QString &zipPath) {
                if (id != artifactId) return;  // Not our artifact

                setLoading(false);
                setStatusMessage(tr("Found %1 SPU file(s) in artifact").arg(spuFiles.size()));
                emit artifactSpuContentsReady(id, name, own, rep, br, spuFiles, zipPath);
            }, Qt::SingleShotConnection);

    connect(_githubClient, &GitHubClient::error, this,
            [this](const QString &message) {
                setLoading(false);
                setStatusMessage(tr("Failed to inspect artifact for SPU files"));
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

    _githubClient->inspectArtifactSpuContents(owner, repo, artifactId, artifactName, branch);
}
