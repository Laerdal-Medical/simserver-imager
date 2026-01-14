/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "mount_helper.h"
#include "platformquirks.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QThread>

#include <cerrno>
#include <cstdio>
#include <cstring>

namespace MountHelper {

QString waitForPartition(const QString &device, int timeoutMs)
{
    // Try common partition naming schemes
    QString partitionPath;

    // For /dev/sdX devices -> /dev/sdX1
    if (device.contains("/dev/sd"))
    {
        partitionPath = device + "1";
    }
    // For /dev/mmcblkX devices -> /dev/mmcblkXp1
    else if (device.contains("/dev/mmcblk"))
    {
        partitionPath = device + "p1";
    }
    // For /dev/nvmeXnY devices -> /dev/nvmeXnYp1
    else if (device.contains("/dev/nvme"))
    {
        partitionPath = device + "p1";
    }
    else
    {
        // Default to sdX-style naming
        partitionPath = device + "1";
    }

    // Wait for partition to be ready for I/O
    if (PlatformQuirks::waitForDeviceReady(partitionPath, timeoutMs))
    {
        qDebug() << "Found partition:" << partitionPath;
        return partitionPath;
    }

    // Try alternate naming pattern for generic devices
    if (!device.contains("/dev/sd") && !device.contains("/dev/mmcblk") && !device.contains("/dev/nvme"))
    {
        QString altPath = device + "p1";
        if (PlatformQuirks::waitForDeviceReady(altPath, 1000))
        {
            qDebug() << "Found partition (alternate):" << altPath;
            return altPath;
        }
    }

    qWarning() << "Timeout waiting for partition on device:" << device;
    return QString();
}

QString getExistingMountPoint(const QString &partition)
{
    // Use standard C file I/O - QFile has issues with /proc files in some contexts
    // Try multiple mount sources: /proc/1/mounts works reliably when running as root via pkexec
    const char* mountFiles[] = {"/proc/1/mounts", "/proc/mounts", "/etc/mtab", nullptr};

    for (int i = 0; mountFiles[i] != nullptr; i++)
    {
        FILE* fp = fopen(mountFiles[i], "r");
        if (!fp)
        {
            continue;
        }

        char line[4096];
        bool foundData = false;

        while (fgets(line, sizeof(line), fp) != nullptr)
        {
            foundData = true;
            QString qline = QString::fromUtf8(line).trimmed();
            QStringList parts = qline.split(' ');

            if (parts.size() >= 2)
            {
                QString device = parts[0];
                QString mountPoint = parts[1];

                if (device == partition)
                {
                    // Decode octal escapes (e.g., \040 for space)
                    mountPoint.replace("\\040", " ");
                    mountPoint.replace("\\011", "\t");
                    qDebug() << "Found existing mount point for" << partition << ":" << mountPoint;
                    fclose(fp);
                    return mountPoint;
                }
            }
        }

        fclose(fp);

        if (foundData)
        {
            // We found a working mount file but partition wasn't in it
            return QString();
        }
    }

    qWarning() << "Could not read any mount information";
    return QString();
}

QString getPartitionPath(const QString &device)
{
    // Determine partition path from device path without waiting for exclusive access
    QString partitionPath;

    // For /dev/sdX devices -> /dev/sdX1
    if (device.contains("/dev/sd"))
    {
        partitionPath = device + "1";
    }
    // For /dev/mmcblkX devices -> /dev/mmcblkXp1
    else if (device.contains("/dev/mmcblk"))
    {
        partitionPath = device + "p1";
    }
    // For /dev/nvmeXnY devices -> /dev/nvmeXnYp1
    else if (device.contains("/dev/nvme"))
    {
        partitionPath = device + "p1";
    }
    else
    {
        // Default to sdX-style naming
        partitionPath = device + "1";
    }

    return partitionPath;
}

QString mountDevice(const QString &device)
{
    // First, determine the partition path
    QString partition = getPartitionPath(device);

    // Check if already mounted BEFORE trying to get exclusive access
    // This avoids timeout when device is already in use by mount
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
    // and we don't need exclusive access to mount - the mount command will handle that

    // Create temporary mount point
    QString mountPoint = QDir::tempPath() + "/laerdal-imager-mount-" +
                         QString::number(QCoreApplication::applicationPid());

    QDir().mkpath(mountPoint);

    // Try udisksctl first (doesn't require root)
    QProcess udisks;
    udisks.start("udisksctl", {"mount", "-b", partition, "--no-user-interaction"});

    if (udisks.waitForFinished(30000) && udisks.exitCode() == 0)
    {
        // Parse mount point from output: "Mounted /dev/sdb1 at /run/media/..."
        QString output = QString::fromUtf8(udisks.readAllStandardOutput());
        QRegularExpression rx("Mounted .* at (.+)");
        QRegularExpressionMatch match = rx.match(output.trimmed());
        if (match.hasMatch())
        {
            QString udisksMountPoint = match.captured(1).trimmed();
            // Remove trailing period if present
            if (udisksMountPoint.endsWith('.'))
            {
                udisksMountPoint.chop(1);
            }
            qDebug() << "Mounted via udisksctl at:" << udisksMountPoint;
            // Remove our unused mount point
            QDir().rmdir(mountPoint);
            return udisksMountPoint;
        }
    }

    // Fall back to system mount command (may require root/pkexec)
    QProcess mount;
    mount.start("mount", {partition, mountPoint});

    if (mount.waitForFinished(30000) && mount.exitCode() == 0)
    {
        qDebug() << "Mounted via mount command at:" << mountPoint;
        return mountPoint;
    }

    // Try with pkexec for elevated privileges
    QProcess pkexecMount;
    pkexecMount.start("pkexec", {"mount", partition, mountPoint});

    if (pkexecMount.waitForFinished(60000) && pkexecMount.exitCode() == 0)
    {
        qDebug() << "Mounted via pkexec mount at:" << mountPoint;
        return mountPoint;
    }

    qWarning() << "Failed to mount partition:" << partition;
    qWarning() << "mount stderr:" << mount.readAllStandardError();

    // Clean up mount point on failure
    QDir().rmdir(mountPoint);
    return QString();
}

bool unmountDevice(const QString &mountPoint)
{
    if (mountPoint.isEmpty())
    {
        return false;
    }

    // Sync filesystem first
    QProcess syncProc;
    syncProc.start("sync");
    syncProc.waitForFinished(30000);

    // Small delay to ensure all writes are flushed
    QThread::msleep(500);

    // Try udisksctl unmount first
    // We need the device path, but we have the mount point
    // Check if this looks like a udisks mount point
    if (mountPoint.startsWith("/run/media/") || mountPoint.startsWith("/media/"))
    {
        QProcess udisks;
        udisks.start("udisksctl", {"unmount", "-p", mountPoint, "--no-user-interaction"});

        if (udisks.waitForFinished(30000) && udisks.exitCode() == 0)
        {
            qDebug() << "Unmounted via udisksctl:" << mountPoint;
            return true;
        }

        // Try with mount point as argument
        udisks.start("udisksctl", {"unmount", "--mount-point", mountPoint, "--no-user-interaction"});
        if (udisks.waitForFinished(30000) && udisks.exitCode() == 0)
        {
            qDebug() << "Unmounted via udisksctl (mount-point):" << mountPoint;
            return true;
        }
    }

    // Try regular umount
    QProcess umount;
    umount.start("umount", {mountPoint});

    if (umount.waitForFinished(30000) && umount.exitCode() == 0)
    {
        qDebug() << "Unmounted via umount:" << mountPoint;
        // Remove mount point directory if it's our temp directory
        if (mountPoint.contains("laerdal-imager-mount"))
        {
            QDir().rmdir(mountPoint);
        }
        return true;
    }

    // Try with pkexec
    QProcess pkexecUmount;
    pkexecUmount.start("pkexec", {"umount", mountPoint});

    if (pkexecUmount.waitForFinished(60000) && pkexecUmount.exitCode() == 0)
    {
        qDebug() << "Unmounted via pkexec umount:" << mountPoint;
        if (mountPoint.contains("laerdal-imager-mount"))
        {
            QDir().rmdir(mountPoint);
        }
        return true;
    }

    // Try lazy unmount as last resort
    QProcess lazyUmount;
    lazyUmount.start("umount", {"-l", mountPoint});

    if (lazyUmount.waitForFinished(30000) && lazyUmount.exitCode() == 0)
    {
        qDebug() << "Lazy unmounted:" << mountPoint;
        if (mountPoint.contains("laerdal-imager-mount"))
        {
            QDir().rmdir(mountPoint);
        }
        return true;
    }

    qWarning() << "Failed to unmount:" << mountPoint;
    return false;
}

QString detectFilesystem(const QString &device)
{
    // First try the partition (e.g., /dev/sdb1) since that's where filesystem lives
    QString partition = device;
    if (!partition.contains("p1") && !partition.endsWith("1"))
    {
        if (partition.contains("/dev/sd"))
        {
            partition += "1";
        }
        else if (partition.contains("/dev/mmcblk") || partition.contains("/dev/nvme"))
        {
            partition += "p1";
        }
        else
        {
            partition += "1";
        }
    }

    // Try partition first
    QProcess blkidPartition;
    blkidPartition.start("blkid", {"-s", "TYPE", "-o", "value", partition});
    if (blkidPartition.waitForFinished(10000) && blkidPartition.exitCode() == 0)
    {
        QString fsType = QString::fromUtf8(blkidPartition.readAllStandardOutput()).trimmed();
        if (!fsType.isEmpty())
        {
            qDebug() << "Detected filesystem on" << partition << ":" << fsType;
            return fsType;
        }
    }

    // Fallback: try the whole device (for superfloppy format without partition table)
    QProcess blkidDevice;
    blkidDevice.start("blkid", {"-s", "TYPE", "-o", "value", device});
    if (blkidDevice.waitForFinished(10000) && blkidDevice.exitCode() == 0)
    {
        QString fsType = QString::fromUtf8(blkidDevice.readAllStandardOutput()).trimmed();
        if (!fsType.isEmpty())
        {
            qDebug() << "Detected filesystem on" << device << ":" << fsType;
            return fsType;
        }
    }

    qWarning() << "Could not detect filesystem on:" << device << "or" << partition;
    return QString();
}

bool isFat32(const QString &device)
{
    QString fsType = detectFilesystem(device);
    // FAT32 is reported as "vfat" by blkid
    return fsType.toLower() == "vfat" || fsType.toLower() == "fat32";
}

bool isCompatibleFilesystem(const QString &device)
{
    QString fsType = detectFilesystem(device).toLower();
    // FAT32, exFAT, and NTFS are all supported by the target Linux devices
    // blkid reports FAT32 as "vfat", exFAT as "exfat", NTFS as "ntfs"
    return fsType == "vfat" || fsType == "fat32" || fsType == "exfat" || fsType == "ntfs";
}

} // namespace MountHelper
