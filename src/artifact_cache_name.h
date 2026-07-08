#ifndef ARTIFACT_CACHE_NAME_H
#define ARTIFACT_CACHE_NAME_H

/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include <QString>
#include <QRegularExpression>
#include <QRegularExpressionMatch>

/*
 * Builds the cache filename for a downloaded GitHub CI artifact ZIP.
 *
 * The GitHub artifact ID is used as the primary cache key. When a version can
 * be parsed from the image/artifact name (same pattern used for OS list
 * sorting), it is appended so cached files are human-identifiable:
 *
 *     artifact_<id>_v<major>.<minor>.<patch>[.<build>].zip
 *
 * When no version can be parsed, falls back to the legacy name so lookups stay
 * backward-compatible with already-cached files:
 *
 *     artifact_<id>.zip
 *
 * All read and write sites MUST use this helper so cache lookups match.
 */
inline QString artifactCacheFileName(qint64 artifactId, const QString &name)
{
    static const QRegularExpression versionRegex(R"(v?(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?)");
    const QRegularExpressionMatch match = versionRegex.match(name);
    if (match.hasMatch()) {
        QString version = match.captured(1) + "." + match.captured(2) + "." + match.captured(3);
        if (!match.captured(4).isEmpty()) {
            version += "." + match.captured(4);
        }
        return QStringLiteral("artifact_%1_v%2.zip")
            .arg(QString::number(artifactId), version);
    }
    return QStringLiteral("artifact_%1.zip").arg(artifactId);
}

#endif // ARTIFACT_CACHE_NAME_H
