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

        // Handle filter change
        if (_githubClient && _selectedSourceType == "github") {
            // Clear existing GitHub artifacts (keep releases in storage)
            QJsonArray releasesOnly;
            for (const auto &item : _githubOsList) {
                QJsonObject obj = item.toObject();
                if (obj["source_type"].toString() == "release") {
                    releasesOnly.append(item);
                }
            }
            _githubOsList = releasesOnly;

            // "RELEASES_ONLY" filter - no need to fetch artifacts, just show releases
            if (branch == QLatin1String("RELEASES_ONLY")) {
                emit osListReady();
                return;
            }

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

        // When switching to GitHub, fetch branches but don't fetch CI images yet
        // CI images will be fetched when user clicks Next on the Source Selection step
        if (sourceType == "github" && _githubClient) {
            qDebug() << "RepositoryManager: Source type set to github, fetching branches...";
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
    } else if (_selectedSourceType == "github") {
        // GitHub only (filtered by branch if applicable)
        QJsonArray githubItems = getGitHubOsList();
        for (const auto &item : githubItems) {
            merged.append(item);
        }
    } else {
        // Default: show both (shouldn't happen with UI)
        for (const auto &item : _cdnOsList) {
            merged.append(item);
        }
        QJsonArray githubItems = getGitHubOsList();
        for (const auto &item : githubItems) {
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
    // Filter options:
    // - Empty ("Default branch"): show releases + default branch artifacts
    // - "RELEASES_ONLY": show only releases (no CI artifacts)
    // - Specific branch: show only CI artifacts from that branch (no releases)
    QJsonArray filtered;

    if (_artifactBranchFilter.isEmpty()) {
        // No filter - show all items (releases + artifacts)
        filtered = _githubOsList;
    } else if (_artifactBranchFilter == QLatin1String("RELEASES_ONLY")) {
        // Releases only - no CI artifacts
        for (const auto &item : _githubOsList) {
            QJsonObject obj = item.toObject();
            if (obj["source_type"].toString() == "release") {
                filtered.append(item);
            }
        }
    } else {
        // Branch filter set - only show artifacts matching the branch (no releases)
        for (const auto &item : _githubOsList) {
            QJsonObject obj = item.toObject();
            if (obj["source_type"].toString() == "artifact") {
                QString artifactBranch = obj["branch"].toString();
                if (artifactBranch == _artifactBranchFilter) {
                    filtered.append(item);
                }
            }
        }
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
        QString icon = "qrc:/qt/qml/RpiImager/icons/use_custom.png";

        for (const auto &assetValue : assets) {
            QJsonObject asset = assetValue.toObject();
            QString assetName = asset["name"].toString().toLower();

            // Detect device from each asset filename
            if (assetName.contains("simman3g-64") || assetName.contains("simman-64")) {
                deviceSet.insert("simman3g-64");
                if (icon.contains("use_custom")) icon = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
            } else if (assetName.contains("simman3g-32") || assetName.contains("simman-32")) {
                deviceSet.insert("simman3g-32");
                if (icon.contains("use_custom")) icon = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
            } else if (assetName.contains("linkbox2")) {
                deviceSet.insert("linkbox2");
            } else if (assetName.contains("linkbox")) {
                deviceSet.insert("linkbox");
            } else if (assetName.contains("cancpu2")) {
                deviceSet.insert("cancpu2");
            } else if (assetName.contains("cancpu")) {
                deviceSet.insert("cancpu");
            } else if (assetName.contains("imx8") || assetName.contains("simpad2")) {
                deviceSet.insert("imx8");
                deviceSet.insert("linkbox2");
                deviceSet.insert("cancpu2");
                if (icon.contains("use_custom")) icon = "qrc:/qt/qml/RpiImager/icons/simpad_plus2.png";
            } else if (assetName.contains("imx6") || assetName.contains("simpad")) {
                deviceSet.insert("imx6");
                deviceSet.insert("linkbox");
                deviceSet.insert("cancpu");
                if (icon.contains("use_custom")) icon = "qrc:/qt/qml/RpiImager/icons/simpad_plus.png";
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
        // SimPad: imx6 = SimPad Plus, imx8 = SimPad Plus 2
        // SimMan: simman3g-64 = 64-bit, simman3g-32 = 32-bit
        // WIC images for SimPad Plus also work on LinkBox and CANCPU devices
        QJsonArray devices;

        if (artifactNameLower.contains("simman3g-64") || artifactNameLower.contains("simman-64")) {
            devices.append("simman3g-64");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
        } else if (artifactNameLower.contains("simman3g-32") || artifactNameLower.contains("simman-32")) {
            devices.append("simman3g-32");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
        } else if (artifactNameLower.contains("linkbox2")) {
            devices.append("linkbox2");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/linkbox2.png";
        } else if (artifactNameLower.contains("linkbox")) {
            devices.append("linkbox");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/linkbox.png";
        } else if (artifactNameLower.contains("cancpu2")) {
            devices.append("cancpu2");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/cancpu2.png";
        } else if (artifactNameLower.contains("cancpu")) {
            devices.append("cancpu");
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/cancpu.png";
        } else if (artifactNameLower.contains("imx8") || artifactNameLower.contains("simpad2")) {
            devices.append("imx8");
            // WIC images for SimPad Plus 2 also work on LinkBox2 and CANCPU2
            if (!isVsi) {
                devices.append("linkbox2");
                devices.append("cancpu2");
            }
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simpad_plus2.png";
        } else if (artifactNameLower.contains("imx6") || artifactNameLower.contains("simpad")) {
            devices.append("imx6");
            // WIC images for SimPad Plus also work on LinkBox and CANCPU
            if (!isVsi) {
                devices.append("linkbox");
                devices.append("cancpu");
            }
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
    QString lower = text.toLower();

    // Check most specific patterns first, then broader ones
    if (lower.contains("simman3g-64") || lower.contains("simman-64")) {
        return QStringLiteral("SimMan 3G (64-bit)");
    } else if (lower.contains("simman3g-32") || lower.contains("simman-32")) {
        return QStringLiteral("SimMan 3G (32-bit)");
    } else if (lower.contains("simman3g") || lower.contains("simman")) {
        return QStringLiteral("SimMan 3G");
    } else if (lower.contains("linkbox2")) {
        return QStringLiteral("LinkBox 2");
    } else if (lower.contains("linkbox")) {
        return QStringLiteral("LinkBox");
    } else if (lower.contains("cancpu2")) {
        return QStringLiteral("CANCPU 2");
    } else if (lower.contains("cancpu")) {
        return QStringLiteral("CANCPU");
    } else if (lower.contains("imx8") || lower.contains("simpad-plus2") || lower.contains("simpad_plus2")
               || lower.contains("simpad plus 2") || lower.contains("simpadplus2")
               || lower.contains("simpad2")) {
        return QStringLiteral("SimPad Plus 2");
    } else if (lower.contains("imx6") || lower.contains("simpad-plus") || lower.contains("simpad_plus")
               || lower.contains("simpad plus") || lower.contains("simpadplus")
               || lower.contains("simpad")) {
        return QStringLiteral("SimPad Plus");
    }
    return QString();
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
    } else if (_selectedSourceType == "github") {
        // GitHub selected - show CI image count
        int imageCount = _githubOsList.size();
        if (imageCount == 0) {
            // Check if there are any enabled repos
            bool hasEnabledRepos = false;
            for (const auto &repo : _githubRepos) {
                if (repo.enabled) {
                    hasEnabledRepos = true;
                    break;
                }
            }
            if (hasEnabledRepos) {
                setStatusMessage(tr("No CI images found for selected repositories"));
            } else {
                setStatusMessage(tr("No GitHub repositories enabled"));
            }
        } else {
            // Show total CI image count - will be updated with filtered count
            // by ImageWriter after device filtering is applied
            setStatusMessage(tr("%1 CI image(s) available").arg(imageCount));
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
    } else if (_selectedSourceType == "github") {
        // GitHub source
        if (filteredCount == 0 && totalCount == 0) {
            // Check if there are any enabled repos
            bool hasEnabledRepos = false;
            for (const auto &repo : _githubRepos) {
                if (repo.enabled) {
                    hasEnabledRepos = true;
                    break;
                }
            }
            if (hasEnabledRepos) {
                setStatusMessage(tr("No CI images found for selected repositories"));
            } else {
                setStatusMessage(tr("No GitHub repositories enabled"));
            }
        } else if (filteredCount == totalCount) {
            setStatusMessage(tr("%1 CI image(s) available").arg(totalCount));
        } else {
            setStatusMessage(tr("%1 CI images available, %2 for this device").arg(totalCount).arg(filteredCount));
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
