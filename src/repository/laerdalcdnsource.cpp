/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "laerdalcdnsource.h"
#include "../devicedetection.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>

LaerdalCdnSource::LaerdalCdnSource(QObject *parent)
    : QObject(parent)
{
}

LaerdalCdnSource::~LaerdalCdnSource()
{
}

void LaerdalCdnSource::fetchList(const QUrl &url)
{
    if (_isFetching) {
        qWarning() << "LaerdalCdnSource: Already fetching";
        return;
    }

    _isFetching = true;

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, "Laerdal-SimServer-Imager");
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = _networkManager.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onNetworkReply(reply);
    });

    qDebug() << "LaerdalCdnSource: Fetching from" << url.toString();
}

void LaerdalCdnSource::onNetworkReply(QNetworkReply *reply)
{
    reply->deleteLater();
    _isFetching = false;

    if (reply->error() != QNetworkReply::NoError) {
        emit error(tr("Failed to fetch CDN list: %1").arg(reply->errorString()));
        return;
    }

    QByteArray responseData = reply->readAll();
    QJsonDocument doc = QJsonDocument::fromJson(responseData);

    if (doc.isNull() || !doc.isObject()) {
        emit error(tr("Invalid JSON response from CDN"));
        return;
    }

    QJsonArray osList = convertLaerdalFormat(doc.object());

    qDebug() << "LaerdalCdnSource: Parsed" << osList.size() << "entries";

    emit listReady(osList);
}

QJsonArray LaerdalCdnSource::convertLaerdalFormat(const QJsonObject &laerdalJson)
{
    QJsonArray osList;

    // The Laerdal format has an "updates" array
    QJsonArray updates = laerdalJson["updates"].toArray();

    for (const auto &updateValue : updates) {
        QJsonObject update = updateValue.toObject();

        QString simpadType = update["simpadtype"].toString();
        QString version = update["version"].toString();
        QString url = update["url"].toString();
        QString md5 = update["md5"].toString();
        QString info = update["info"].toString();
        QString releaseNotes = update["releasenotes"].toString();
        double imageDownloadSize = update["image_download_size"].toDouble();
        double extractSize = update["extract_size"].toDouble();

        // Create OS list entry
        QJsonObject osEntry;

        // Detect device type from structured CDN simpadType
        auto deviceType = DeviceDetection::detectFromCdnType(simpadType);
        bool isVsi = url.toLower().endsWith(".vsi");

        // Name with device type and version
        QString deviceName = DeviceDetection::getDisplayName(deviceType);
        if (deviceName.isEmpty()) {
            // Unknown type: capitalize first letter as fallback
            deviceName = simpadType;
            if (!deviceName.isEmpty())
                deviceName[0] = deviceName[0].toUpper();
        }
        osEntry["name"] = QString("%1 v%2").arg(deviceName, version);

        // Description from info field
        osEntry["description"] = info.isEmpty() ? releaseNotes : info;

        // Download URL
        osEntry["url"] = url;

        // MD5 hash (convert to our expected format)
        // Note: We use MD5 from Laerdal, but the imager typically expects SHA256
        // For compatibility, store as extract_md5 and handle in download thread
        osEntry["extract_md5"] = md5;

        // Download and extract sizes for progress tracking
        osEntry["image_download_size"] = imageDownloadSize;
        osEntry["extract_size"] = extractSize;

        // Mark as no customization support (WIC files don't support cloud-init)
        osEntry["init_format"] = "none";

        // Device tags for filtering (include cross-device compatibility)
        osEntry["devices"] = DeviceDetection::getDeviceTags(deviceType, isVsi);

        // Icon based on device type
        osEntry["icon"] = DeviceDetection::getIconPath(deviceType);

        // Source identifier
        osEntry["source"] = "laerdal_cdn";

        // Full release notes if available
        if (!releaseNotes.isEmpty()) {
            osEntry["release_notes"] = releaseNotes;
        }

        osList.append(osEntry);
    }

    return osList;
}

