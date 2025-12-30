/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#ifndef LAERDALCDNSOURCE_H
#define LAERDALCDNSOURCE_H

#include <QObject>
#include <QUrl>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QNetworkReply>

/**
 * @brief Fetches and parses the Laerdal CDN updates.json format
 *
 * The Laerdal CDN format:
 * {
 *   "updates": [
 *     {
 *       "simpadtype": "plus",
 *       "version": "9.2.0.127",
 *       "url": "https://...",
 *       "md5": "...",
 *       "info": "...",
 *       "releasenotes": "..."
 *     }
 *   ]
 * }
 */
class LaerdalCdnSource : public QObject
{
    Q_OBJECT

public:
    explicit LaerdalCdnSource(QObject *parent = nullptr);
    virtual ~LaerdalCdnSource();

    /**
     * @brief Fetch the OS list from a CDN URL
     * @param url URL to the updates.json file
     */
    void fetchList(const QUrl &url);

    /**
     * @brief Check if currently fetching
     */
    bool isFetching() const { return _isFetching; }

signals:
    /**
     * @brief Emitted when the list is ready
     * @param list Array of OS entries in standard format
     */
    void listReady(const QJsonArray &list);

    /**
     * @brief Emitted on fetch error
     * @param message Error message
     */
    void error(const QString &message);

private slots:
    void onNetworkReply(QNetworkReply *reply);

private:
    /**
     * @brief Convert Laerdal CDN format to standard OS list format
     * @param laerdalJson The raw JSON from the CDN
     * @return Array in standard OS list format
     */
    QJsonArray convertLaerdalFormat(const QJsonObject &laerdalJson);

    /**
     * @brief Map simpadtype to device tags
     * @param simpadType The simpadtype field value
     * @return Device tag (e.g., "imx6", "imx8")
     */
    QString mapSimpadTypeToTag(const QString &simpadType);

    /**
     * @brief Get display name for simpadtype
     */
    QString getDisplayName(const QString &simpadType, const QString &version);

    QNetworkAccessManager _networkManager;
    bool _isFetching = false;
};

#endif // LAERDALCDNSOURCE_H
