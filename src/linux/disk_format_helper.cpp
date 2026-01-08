/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "disk_format_helper.h"
#include "platformquirks.h"
#include "dependencies/mountutils/src/mountutils.hpp"

#include <QDebug>
#include <QFile>
#include <QProcess>
#include <QThread>

#include <unistd.h>

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
        // Continue anyway, mkfs might handle it
    }

    qDebug() << "DiskFormatHelper: Creating partition table on:" << device;

    // Check if we're already running with elevated privileges
    bool isRoot = (geteuid() == 0);
    qDebug() << "DiskFormatHelper: Running as root:" << isRoot;

    // Use sfdisk to create a single FAT32 partition
    // --force: Override checks (disk may still appear "in use" right after unmount)
    // --wipe always: Wipe existing filesystem signatures
    // If not root, use pkexec for elevation
    QProcess sfdiskProc;
    if (isRoot)
    {
        sfdiskProc.start("sfdisk", {"--force", "--wipe", "always", device});
    }
    else
    {
        sfdiskProc.start("pkexec", {"sfdisk", "--force", "--wipe", "always", device});
    }

    if (!sfdiskProc.waitForStarted(10000))
    {
        result.errorMessage = "Failed to start sfdisk";
        return result;
    }

    // Create a single partition using all space, type 0x0c (FAT32 LBA)
    sfdiskProc.write("label: dos\n");
    sfdiskProc.write("type=c\n");  // FAT32 LBA
    sfdiskProc.closeWriteChannel();

    if (!sfdiskProc.waitForFinished(60000) || sfdiskProc.exitCode() != 0)
    {
        QString sfdiskError = QString::fromUtf8(sfdiskProc.readAllStandardError());
        QString sfdiskOut = QString::fromUtf8(sfdiskProc.readAllStandardOutput());
        qWarning() << "DiskFormatHelper: sfdisk failed:" << sfdiskError << sfdiskOut;
        if (sfdiskProc.exitCode() == 126)
        {
            result.errorMessage = "Authentication cancelled or failed";
        }
        else
        {
            result.errorMessage = QString("Failed to create partition: %1").arg(sfdiskError.isEmpty() ? sfdiskOut : sfdiskError);
        }
        return result;
    }

    qDebug() << "DiskFormatHelper: Partition table created successfully";

    // Wait for kernel to recognize the new partition
    QThread::msleep(500);

    // Trigger partition re-read
    QProcess partprobeProc;
    if (isRoot)
    {
        partprobeProc.start("partprobe", {device});
    }
    else
    {
        partprobeProc.start("pkexec", {"partprobe", device});
    }
    partprobeProc.waitForFinished(15000);

    // Wait a bit more for udev
    QThread::msleep(1000);

    // Determine partition path
    QString partitionPath = device;
    if (device.contains("/dev/sd"))
    {
        partitionPath = device + "1";
    }
    else if (device.contains("/dev/mmcblk") || device.contains("/dev/nvme"))
    {
        partitionPath = device + "p1";
    }
    else
    {
        partitionPath = device + "1";
    }

    // Wait for partition to exist
    int waitTime = 0;
    while (!QFile::exists(partitionPath) && waitTime < 5000)
    {
        QThread::msleep(100);
        waitTime += 100;
    }

    if (!QFile::exists(partitionPath))
    {
        result.errorMessage = QString("Partition %1 did not appear after formatting").arg(partitionPath);
        return result;
    }

    qDebug() << "DiskFormatHelper: Formatting partition:" << partitionPath;

    // Format with mkfs.fat
    QProcess mkfsProc;
    if (isRoot)
    {
        mkfsProc.start("mkfs.fat", {"-F", "32", "-n", volumeLabel, partitionPath});
    }
    else
    {
        mkfsProc.start("pkexec", {"mkfs.fat", "-F", "32", "-n", volumeLabel, partitionPath});
    }

    if (!mkfsProc.waitForFinished(120000) || mkfsProc.exitCode() != 0)
    {
        QString mkfsError = QString::fromUtf8(mkfsProc.readAllStandardError());
        QString mkfsOut = QString::fromUtf8(mkfsProc.readAllStandardOutput());
        qWarning() << "DiskFormatHelper: mkfs.fat failed:" << mkfsError << mkfsOut;
        if (mkfsProc.exitCode() == 126)
        {
            result.errorMessage = "Authentication cancelled or failed";
        }
        else
        {
            result.errorMessage = QString("Failed to format partition: %1").arg(mkfsError.isEmpty() ? mkfsOut : mkfsError);
        }
        return result;
    }

    qDebug() << "DiskFormatHelper: Format completed successfully";

    // Wait for the OS to recognize the filesystem
    QThread::sleep(2);

    result.success = true;
    return result;
}

} // namespace DiskFormatHelper
