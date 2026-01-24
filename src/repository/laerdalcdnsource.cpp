/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "laerdalcdnsource.h"
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

        // Name with device type and version
        osEntry["name"] = getDisplayName(simpadType, version);

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

        // Device tag for filtering
        QString tag = mapSimpadTypeToTag(simpadType);
        osEntry["devices"] = QJsonArray({tag});

        // Icon based on device type
        if (simpadType.contains("plus2", Qt::CaseInsensitive) ||
            simpadType.contains("imx8", Qt::CaseInsensitive)) {
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simpad_plus2.png";
        } else if (simpadType.contains("plus", Qt::CaseInsensitive) ||
                   simpadType.contains("imx6", Qt::CaseInsensitive)) {
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simpad_plus.png";
        } else if (simpadType.contains("simman", Qt::CaseInsensitive)) {
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
        } else {
            osEntry["icon"] = "qrc:/qt/qml/RpiImager/icons/use_custom.png";
        }

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

QString LaerdalCdnSource::mapSimpadTypeToTag(const QString &simpadType)
{
    QString type = simpadType.toLower();

    if (type == "plus" || type == "imx6") {
        return "imx6";
    }
    if (type == "plus2" || type == "imx8") {
        return "imx8";
    }
    if (type.contains("simman") && type.contains("32")) {
        return "simman3g-32";
    }
    if (type.contains("simman") && type.contains("64")) {
        return "simman3g-64";
    }

    // Default to the type as-is
    return type;
}

QString LaerdalCdnSource::getDisplayName(const QString &simpadType, const QString &version)
{
    QString type = simpadType.toLower();
    QString deviceName;

    if (type == "plus" || type == "imx6") {
        deviceName = "SimPad Plus";
    } else if (type == "plus2" || type == "imx8") {
        deviceName = "SimPad Plus 2";
    } else if (type.contains("simman") && type.contains("32")) {
        deviceName = "SimMan 3G (32-bit)";
    } else if (type.contains("simman") && type.contains("64")) {
        deviceName = "SimMan 3G (64-bit)";
    } else {
        // Capitalize first letter
        deviceName = simpadType;
        if (!deviceName.isEmpty()) {
            deviceName[0] = deviceName[0].toUpper();
        }
    }

    return QString("%1 v%2").arg(deviceName, version);
}
