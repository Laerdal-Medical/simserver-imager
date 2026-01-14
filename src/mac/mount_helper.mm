/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "mount_helper.h"
#include "../platformquirks.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QThread>

#import <Foundation/Foundation.h>
#import <DiskArbitration/DiskArbitration.h>

namespace MountHelper {

// Internal helper to get partition path from device
static QString getPartitionPath(const QString &device)
{
    // On macOS, partitions are named like /dev/disk2s1
    return device + "s1";
}

// Internal helper to check if partition is already mounted
static QString getExistingMountPoint(const QString &partition)
{
    // Use diskutil info to check if already mounted
    QProcess diskutilInfo;
    diskutilInfo.start("diskutil", {"info", partition});

    if (diskutilInfo.waitForFinished(5000) && diskutilInfo.exitCode() == 0)
    {
        QString info = QString::fromUtf8(diskutilInfo.readAllStandardOutput());
        QStringList lines = info.split('\n');

        for (const QString &line : lines)
        {
            if (line.trimmed().startsWith("Mount Point:"))
            {
                QString mountPoint = line.mid(line.indexOf(':') + 1).trimmed();
                if (!mountPoint.isEmpty() && mountPoint != "(not mounted)")
                {
                    qDebug() << "Found existing mount point for" << partition << ":" << mountPoint;
                    return mountPoint;
                }
            }
        }
    }

    return QString();
}

QString waitForPartition(const QString &device, int timeoutMs)
{
    // On macOS, device is like "/dev/disk2"
    // After formatting, the partition appears as "/dev/disk2s1"

    QString partitionPath = device + "s1";

    // Wait for partition to be ready for I/O
    if (PlatformQuirks::waitForDeviceReady(partitionPath, timeoutMs))
    {
        qDebug() << "Found partition:" << partitionPath;
        return partitionPath;
    }

    qWarning() << "Timeout waiting for partition on device:" << device;
    return QString();
}

QString mountDevice(const QString &device)
{
    // First, determine the partition path
    QString partition = getPartitionPath(device);

    // Check if already mounted BEFORE trying to get exclusive access
    // This avoids waiting when device is already in use by mount
    QString existingMount = getExistingMountPoint(partition);
    if (!existingMount.isEmpty())
    {
        qDebug() << "Device" << partition << "already mounted at:" << existingMount;
        return existingMount;
    }

    // Also check if the whole device (superfloppy) is mounted
    existingMount = getExistingMountPoint(device);
    if (!existingMount.isEmpty())
    {
        qDebug() << "Device" << device << "(superfloppy) already mounted at:" << existingMount;
        return existingMount;
    }

    // Check if partition file exists to determine the device layout
    QFile partitionFile(partition);
    QFile deviceFile(device);

    if (!partitionFile.exists())
    {
        qDebug() << "Partition" << partition << "does not exist, checking for superfloppy format";
        // Device might be in superfloppy format (filesystem on whole device, no partition table)
        if (deviceFile.exists())
        {
            qDebug() << "Using superfloppy format (no partition table):" << device;
            partition = device;
            // Don't wait for exclusive access - just use the device path for mounting
        }
        else
        {
            // Neither partition nor device exists - wait for partition to appear
            // This typically happens right after formatting when kernel re-reads partition table
            partition = waitForPartition(device);
            if (partition.isEmpty())
            {
                qWarning() << "No partition found for device:" << device;
                return QString();
            }
        }
    }
    // If partition exists but is not currently mounted, we can proceed to mount it
    // Note: We skip waitForPartition() here because we already verified the partition exists
    // and we don't need exclusive access to mount - diskutil will handle that

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

bool isCompatibleFilesystem(const QString &device)
{
    QString fsType = detectFilesystem(device).toLower();
    // FAT32, exFAT, and NTFS are all supported by the target Linux devices
    // macOS reports: FAT32 as "msdos"/"fat32", exFAT as "exfat", NTFS as "ntfs"
    return fsType.contains("fat32") || fsType.contains("msdos") || fsType == "fat" ||
           fsType == "exfat" || fsType == "ntfs";
}

} // namespace MountHelper
