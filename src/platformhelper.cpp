/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

#include "platformhelper.h"
#include "platformquirks.h"
#include <QDir>
#include <QFileInfo>

QUrl PlatformHelper::localFileUrl(const QString &path) const
{
    QString value = path.trimmed();
    if (value.startsWith("file///"))
        return QUrl::fromLocalFile(value.mid(6));
    if (value == "~" || value.startsWith("~/"))
        value = QDir::homePath() + value.mid(1);
    if (QDir::isAbsolutePath(value))
        return QUrl::fromLocalFile(value);
    const QUrl url(value);
    return url.isLocalFile() && QDir::isAbsolutePath(url.toLocalFile()) ? url : QUrl();
}

bool PlatformHelper::directoryExists(const QUrl &url) const
{
    return url.isLocalFile() && QFileInfo(url.toLocalFile()).isDir();
}
bool PlatformHelper::hasNetworkConnectivity() const
{
    return PlatformQuirks::hasNetworkConnectivity();
}

void PlatformHelper::beep() const
{
    PlatformQuirks::beep();
}

bool PlatformHelper::isScrollInverted(bool qtInvertedFlag) const
{
    return PlatformQuirks::isScrollInverted(qtInvertedFlag);
}
