/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "mount_helper.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QThread>

#import <Foundation/Foundation.h>
#import <DiskArbitration/DiskArbitration.h>

namespace MountHelper {

QString waitForPartition(const QString &device, int timeoutMs)
{
    // On macOS, device is like "/dev/disk2"
    // After formatting, the partition appears as "/dev/disk2s1"

    QString partitionPath = device + "s1";

    int elapsed = 0;
    const int pollInterval = 100; // ms

    while (elapsed < timeoutMs)
    {
        if (QFile::exists(partitionPath))
        {
            qDebug() << "Found partition:" << partitionPath;
            return partitionPath;
        }

        QThread::msleep(pollInterval);
        elapsed += pollInterval;
    }

    qWarning() << "Timeout waiting for partition on device:" << device;
    return QString();
}

QString mountDevice(const QString &device)
{
    // Wait for partition to appear
    QString partition = waitForPartition(device);
    if (partition.isEmpty())
    {
        qWarning() << "No partition found for device:" << device;
        return QString();
    }

    // On macOS, we can use diskutil to mount
    QProcess diskutil;
    diskutil.start("diskutil", {"mount", partition});

    if (diskutil.waitForFinished(30000) && diskutil.exitCode() == 0)
    {
        // Parse output to find mount point: "Volume NAME on /dev/disk2s1 mounted"
        QString output = QString::fromUtf8(diskutil.readAllStandardOutput());
        qDebug() << "diskutil mount output:" << output;

        // The volume is typically mounted at /Volumes/<volume_name>
        // We can use diskutil info to get the exact mount point
        QProcess diskutilInfo;
        diskutilInfo.start("diskutil", {"info", partition});

        if (diskutilInfo.waitForFinished(10000) && diskutilInfo.exitCode() == 0)
        {
            QString info = QString::fromUtf8(diskutilInfo.readAllStandardOutput());
            // Look for "Mount Point:" line
            QStringList lines = info.split('\n');
            for (const QString &line : lines)
            {
                if (line.trimmed().startsWith("Mount Point:"))
                {
                    QString mountPoint = line.mid(line.indexOf(':') + 1).trimmed();
                    if (!mountPoint.isEmpty() && mountPoint != "(not mounted)")
                    {
                        qDebug() << "Mounted at:" << mountPoint;
                        return mountPoint;
                    }
                }
            }
        }

        // Fallback: try common mount points
        QProcess mount;
        mount.start("mount");
        if (mount.waitForFinished(5000))
        {
            QString mountOutput = QString::fromUtf8(mount.readAllStandardOutput());
            QStringList mountLines = mountOutput.split('\n');
            for (const QString &line : mountLines)
            {
                if (line.contains(partition))
                {
                    // Format: "/dev/disk2s1 on /Volumes/UNTITLED type msdos ..."
                    int onIndex = line.indexOf(" on ");
                    int typeIndex = line.indexOf(" type ", onIndex);
                    if (onIndex != -1 && typeIndex != -1)
                    {
                        QString mountPoint = line.mid(onIndex + 4, typeIndex - onIndex - 4).trimmed();
                        qDebug() << "Found mount point from mount command:" << mountPoint;
                        return mountPoint;
                    }
                }
            }
        }
    }
    else
    {
        qWarning() << "diskutil mount failed:" << diskutil.readAllStandardError();
    }

    qWarning() << "Failed to mount partition:" << partition;
    return QString();
}

bool unmountDevice(const QString &mountPoint)
{
    if (mountPoint.isEmpty())
    {
        return false;
    }

    // Sync first
    QProcess syncProc;
    syncProc.start("sync");
    syncProc.waitForFinished(30000);

    // Small delay to ensure all writes are flushed
    QThread::msleep(500);

    // Use diskutil to unmount
    QProcess diskutil;
    diskutil.start("diskutil", {"unmount", mountPoint});

    if (diskutil.waitForFinished(30000) && diskutil.exitCode() == 0)
    {
        qDebug() << "Unmounted via diskutil:" << mountPoint;
        return true;
    }

    // Try with force option
    diskutil.start("diskutil", {"unmount", "force", mountPoint});
    if (diskutil.waitForFinished(30000) && diskutil.exitCode() == 0)
    {
        qDebug() << "Force unmounted via diskutil:" << mountPoint;
        return true;
    }

    qWarning() << "Failed to unmount:" << mountPoint;
    qWarning() << "diskutil stderr:" << diskutil.readAllStandardError();
    return false;
}

QString detectFilesystem(const QString &device)
{
    // First try the partition (e.g., /dev/disk2s1) since that's where filesystem lives
    QString partition = device;
    if (!device.contains("s") || QRegularExpression("disk\\d+$").match(device).hasMatch())
    {
        partition = device + "s1";
    }

    // Try partition first if it exists
    if (partition != device && QFile::exists(partition))
    {
        QProcess diskutilPartition;
        diskutilPartition.start("diskutil", {"info", partition});

        if (diskutilPartition.waitForFinished(10000) && diskutilPartition.exitCode() == 0)
        {
            QString info = QString::fromUtf8(diskutilPartition.readAllStandardOutput());
            QStringList lines = info.split('\n');

            for (const QString &line : lines)
            {
                QString trimmed = line.trimmed();
                if (trimmed.startsWith("File System Personality:") ||
                    trimmed.startsWith("Type (Bundle):"))
                {
                    QString fsType = trimmed.mid(trimmed.indexOf(':') + 1).trimmed().toLower();
                    if (!fsType.isEmpty())
                    {
                        qDebug() << "Detected filesystem on" << partition << ":" << fsType;
                        return fsType;
                    }
                }
            }
        }
    }

    // Fallback: try the whole device (for superfloppy format)
    QProcess diskutilDevice;
    diskutilDevice.start("diskutil", {"info", device});

    if (diskutilDevice.waitForFinished(10000) && diskutilDevice.exitCode() == 0)
    {
        QString info = QString::fromUtf8(diskutilDevice.readAllStandardOutput());
        QStringList lines = info.split('\n');

        for (const QString &line : lines)
        {
            QString trimmed = line.trimmed();
            if (trimmed.startsWith("File System Personality:") ||
                trimmed.startsWith("Type (Bundle):"))
            {
                QString fsType = trimmed.mid(trimmed.indexOf(':') + 1).trimmed().toLower();
                if (!fsType.isEmpty())
                {
                    qDebug() << "Detected filesystem on" << device << ":" << fsType;
                    return fsType;
                }
            }
        }
    }

    qWarning() << "Could not detect filesystem on:" << device;
    return QString();
}

bool isFat32(const QString &device)
{
    QString fsType = detectFilesystem(device);
    // macOS reports FAT32 as "MS-DOS FAT32" or "FAT32"
    return fsType.contains("fat32") || fsType.contains("msdos") || fsType == "fat";
}

} // namespace MountHelper
