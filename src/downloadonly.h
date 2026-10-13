/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
#pragma once

#include <QObject>
#include <QThread>
#include <QUrl>
#include <QVariantMap>
#include <atomic>
#include <functional>
#ifndef CLI_ONLY_BUILD
#include <QQmlEngine>
#endif

class DownloadOnly : public QObject
{
    Q_OBJECT
#ifndef CLI_ONLY_BUILD
    QML_ELEMENT
    QML_UNCREATABLE("Owned by ImageWriter")
#endif
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(qint64 received READ received NOTIFY changed)
    Q_PROPERTY(qint64 total READ total NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QUrl savedFile READ savedFile NOTIFY changed)
public:
    explicit DownloadOnly(QObject *parent = nullptr);
    ~DownloadOnly() override;
    bool busy() const { return _busy; }
    qint64 received() const { return _received; }
    qint64 total() const { return _total; }
    QString status() const { return _status; }
    QString error() const { return _error; }
    QUrl savedFile() const { return _savedFile; }
    void start(const QVariantMap &source, const QUrl &destination, const QString &token, bool overwrite);
    void setFolderLauncher(std::function<bool(const QUrl &)> launcher);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE bool destinationExists(const QUrl &destination) const;
    Q_INVOKABLE QString suggestedFilename(const QVariantMap &source) const;
    Q_INVOKABLE bool openContainingFolder();
    Q_INVOKABLE bool openCacheFolder();
signals:
    void changed();
private:
    void progress(qint64 received, qint64 total, const QString &status);
    bool openFolder(const QString &path);
    std::function<bool(const QUrl &)> _folderLauncher;
    QThread *_worker = nullptr;
    std::atomic<bool> _cancelled{false};
    bool _busy = false;
    qint64 _received = 0, _total = 0;
    QString _status, _error;
    QUrl _savedFile;
};
