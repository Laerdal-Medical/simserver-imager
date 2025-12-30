/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "githubsource.h"
#include "../github/githubclient.h"
#include <QDebug>
#include <QJsonObject>

GitHubSource::GitHubSource(const QString &owner, const QString &repo, QObject *parent)
    : QObject(parent)
    , _owner(owner)
    , _repo(repo)
{
}

GitHubSource::~GitHubSource()
{
}

void GitHubSource::setGitHubClient(GitHubClient *client)
{
    if (_githubClient) {
        disconnect(_githubClient, nullptr, this, nullptr);
    }

    _githubClient = client;

    if (_githubClient) {
        // Note: We connect to specific signals and filter by owner/repo
        // since multiple GitHubSource instances may share the same client
        connect(_githubClient, &GitHubClient::wicFilesReady,
                this, &GitHubSource::onWicFilesReceived);
        connect(_githubClient, &GitHubClient::artifactWicFilesReady,
                this, &GitHubSource::onArtifactWicFilesReceived);
        connect(_githubClient, &GitHubClient::fileUrlReady,
                this, &GitHubSource::onFileUrlReceived);
        connect(_githubClient, &GitHubClient::error,
                this, &GitHubSource::onError);
    }
}

void GitHubSource::searchReleasesForWicFiles()
{
    if (!_githubClient) {
        emit error(tr("GitHub client not configured"));
        return;
    }

    if (!_enabled) {
        qDebug() << "GitHubSource: Repo" << fullName() << "is disabled, skipping";
        return;
    }

    qDebug() << "GitHubSource: Searching WIC files in" << fullName();
    _githubClient->searchWicFilesInReleases(_owner, _repo);
}

void GitHubSource::searchArtifactsForWicFiles(const QString &branch)
{
    if (!_githubClient) {
        emit error(tr("GitHub client not configured"));
        return;
    }

    if (!_enabled) {
        qDebug() << "GitHubSource: Repo" << fullName() << "is disabled, skipping";
        return;
    }

    qDebug() << "GitHubSource: Searching WIC artifacts in" << fullName();
    _githubClient->searchWicFilesInArtifacts(_owner, _repo, branch);
}

void GitHubSource::getFileFromBranch(const QString &branch, const QString &path)
{
    if (!_githubClient) {
        emit error(tr("GitHub client not configured"));
        return;
    }

    qDebug() << "GitHubSource: Getting file" << path << "from branch" << branch
             << "in" << fullName();
    _githubClient->fetchBranchFile(_owner, _repo, branch, path);
}

void GitHubSource::getFileFromTag(const QString &tag, const QString &path)
{
    if (!_githubClient) {
        emit error(tr("GitHub client not configured"));
        return;
    }

    qDebug() << "GitHubSource: Getting file" << path << "from tag" << tag
             << "in" << fullName();
    _githubClient->fetchTagFile(_owner, _repo, tag, path);
}

void GitHubSource::onWicFilesReceived(const QJsonArray &wicFiles)
{
    // Store the WIC files
    _wicFiles = wicFiles;

    // Add source information to each entry
    QJsonArray enrichedFiles;
    for (const auto &fileValue : wicFiles) {
        QJsonObject file = fileValue.toObject();
        file["source_repo"] = fullName();
        file["source_owner"] = _owner;
        file["source_repo_name"] = _repo;
        file["source_type"] = "release";
        enrichedFiles.append(file);
    }

    emit wicFilesReady(enrichedFiles);
}

void GitHubSource::onArtifactWicFilesReceived(const QJsonArray &wicFiles)
{
    // Add source information to each entry
    QJsonArray enrichedFiles;
    for (const auto &fileValue : wicFiles) {
        QJsonObject file = fileValue.toObject();
        file["source_repo"] = fullName();
        file["source_owner"] = _owner;
        file["source_repo_name"] = _repo;
        file["source_type"] = "artifact";
        enrichedFiles.append(file);
    }

    emit artifactWicFilesReady(enrichedFiles);
}

void GitHubSource::onFileUrlReceived(const QString &downloadUrl, const QString &fileName)
{
    emit fileReady(downloadUrl, fileName);
}

void GitHubSource::onError(const QString &message)
{
    emit error(message);
}
