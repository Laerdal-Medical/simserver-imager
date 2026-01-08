/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "disk_format_helper.h"
#include "platformquirks.h"
#include "dependencies/mountutils/src/mountutils.hpp"

#include <QDebug>
#include <QProcess>
#include <QThread>

namespace DiskFormatHelper {

FormatResult formatDeviceFat32(const QString &device, const QString &volumeLabel)
{
    FormatResult result;

    // Unmount before formatting
    QString unmountPath = PlatformQuirks::getEjectDevicePath(device);
    qDebug() << "DiskFormatHelper: Unmounting before format:" << unmountPath;
    MOUNTUTILS_RESULT unmountResult = unmount_disk(unmountPath.toUtf8().constData());
    if (unmountResult != MOUNTUTILS_SUCCESS)
    {
        qWarning() << "DiskFormatHelper: Failed to unmount before format:" << unmountResult;
        // Continue anyway, diskutil might handle it
    }

    qDebug() << "DiskFormatHelper: Formatting device with diskutil:" << device;

    // diskutil eraseDisk FAT32 LAERDAL MBRFormat /dev/diskN
    QProcess diskutilProc;
    diskutilProc.start("diskutil", {"eraseDisk", "FAT32", volumeLabel, "MBRFormat", device});

    if (!diskutilProc.waitForFinished(120000) || diskutilProc.exitCode() != 0)
    {
        QString diskutilError = QString::fromUtf8(diskutilProc.readAllStandardError());
        QString diskutilOut = QString::fromUtf8(diskutilProc.readAllStandardOutput());
        qWarning() << "DiskFormatHelper: diskutil failed:" << diskutilError << diskutilOut;
        result.errorMessage = QString("Failed to format drive: %1").arg(diskutilError.isEmpty() ? diskutilOut : diskutilError);
        return result;
    }

    qDebug() << "DiskFormatHelper: Format completed successfully";

    // Wait for the OS to recognize the new partition
    QThread::sleep(2);

    result.success = true;
    return result;
}

} // namespace DiskFormatHelper
