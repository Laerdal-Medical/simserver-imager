/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "mount_helper.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QThread>

#include <windows.h>
#include <fileapi.h>
#include <handleapi.h>

namespace MountHelper {

// Internal helper to get the drive letter for an already-mounted device
static QString getExistingDriveLetter(const QString &device)
{
    // On Windows, check if the physical drive already has a drive letter assigned
    // This avoids waiting for a drive that's already mounted
    Q_UNUSED(device)

    DWORD drives = GetLogicalDrives();
    for (char letter = 'D'; letter <= 'Z'; letter++)
    {
        if (drives & (1 << (letter - 'A')))
        {
            QString drivePath = QString("%1:\\").arg(letter);
            UINT driveType = GetDriveTypeA(drivePath.toLatin1().constData());
            if (driveType == DRIVE_REMOVABLE)
            {
                // Found a removable drive
                qDebug() << "Found existing removable drive:" << drivePath;
                return QString("%1:").arg(letter);
            }
        }
    }

    return QString();
}

QString waitForPartition(const QString &device, int timeoutMs)
{
    // On Windows, device is like "\\.\PhysicalDrive1"
    // After formatting, the partition appears as a drive letter
    // We need to wait for Windows to assign a drive letter

    Q_UNUSED(device)

    int elapsed = 0;
    const int pollInterval = 100; // ms

    // Wait for the new volume to appear
    // Windows will auto-assign a drive letter after formatting
    while (elapsed < timeoutMs)
    {
        // Check for new removable drives
        DWORD drives = GetLogicalDrives();
        for (char letter = 'D'; letter <= 'Z'; letter++)
        {
            if (drives & (1 << (letter - 'A')))
            {
                QString drivePath = QString("%1:\\").arg(letter);
                UINT driveType = GetDriveTypeA(drivePath.toLatin1().constData());
                if (driveType == DRIVE_REMOVABLE)
                {
                    // Found a removable drive - check if it's our newly formatted one
                    // This is a simplified check; ideally we'd match by physical drive
                    qDebug() << "Found removable drive:" << drivePath;
                    return QString("%1:").arg(letter);
                }
            }
        }

        QThread::msleep(pollInterval);
        elapsed += pollInterval;
    }

    qWarning() << "Timeout waiting for partition on device:" << device;
    return QString();
}

QString mountDevice(const QString &device)
{
    // On Windows, removable drives are typically auto-mounted
    // We just need to find the drive letter associated with the physical drive

    // First check if already mounted - avoid waiting for a drive that's already available
    QString existingDrive = getExistingDriveLetter(device);
    if (!existingDrive.isEmpty())
    {
        QString mountPoint = existingDrive + "\\";
        qDebug() << "Device already mounted at:" << mountPoint;
        return mountPoint;
    }

    // Wait for partition to appear and get drive letter
    QString driveLetter = waitForPartition(device);
    if (driveLetter.isEmpty())
    {
        qWarning() << "No partition found for device:" << device;
        return QString();
    }

    // On Windows, the "mount point" is just the drive letter with backslash
    QString mountPoint = driveLetter + "\\";
    qDebug() << "Device is mounted at:" << mountPoint;
    return mountPoint;
}

bool unmountDevice(const QString &mountPoint)
{
    if (mountPoint.isEmpty())
    {
        return false;
    }

    // Extract drive letter from mount point (e.g., "D:\" -> "D:")
    QString driveLetter = mountPoint.left(2);
    if (!driveLetter.endsWith(':'))
    {
        driveLetter = mountPoint.left(1) + ":";
    }

    qDebug() << "Ejecting drive:" << driveLetter;

    // Flush file buffers
    QString volumePath = "\\\\.\\" + driveLetter;
    HANDLE hVolume = CreateFileA(
        volumePath.toLatin1().constData(),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        NULL,
        OPEN_EXISTING,
        0,
        NULL);

    if (hVolume != INVALID_HANDLE_VALUE)
    {
        // Flush the volume
        FlushFileBuffers(hVolume);

        // Lock the volume
        DWORD bytesReturned;
        BOOL locked = DeviceIoControl(hVolume, FSCTL_LOCK_VOLUME, NULL, 0, NULL, 0, &bytesReturned, NULL);
        if (!locked)
        {
            qWarning() << "Failed to lock volume:" << GetLastError();
        }

        // Dismount the volume
        BOOL dismounted = DeviceIoControl(hVolume, FSCTL_DISMOUNT_VOLUME, NULL, 0, NULL, 0, &bytesReturned, NULL);
        if (!dismounted)
        {
            qWarning() << "Failed to dismount volume:" << GetLastError();
        }

        // Unlock the volume
        DeviceIoControl(hVolume, FSCTL_UNLOCK_VOLUME, NULL, 0, NULL, 0, &bytesReturned, NULL);

        CloseHandle(hVolume);

        if (dismounted)
        {
            qDebug() << "Successfully unmounted:" << mountPoint;
            return true;
        }
    }
    else
    {
        qWarning() << "Failed to open volume:" << GetLastError();
    }

    qWarning() << "Failed to unmount:" << mountPoint;
    return false;
}

QString detectFilesystem(const QString &device)
{
    QString drivePath;

    // Check if device is a physical drive path (e.g., "\\.\PhysicalDrive1")
    // or already a drive letter (e.g., "D:" or "D:\")
    if (device.contains("PhysicalDrive"))
    {
        // Find the drive letter associated with this physical drive
        // Scan all removable drives and check if they match
        DWORD drives = GetLogicalDrives();
        for (char letter = 'D'; letter <= 'Z'; letter++)
        {
            if (drives & (1 << (letter - 'A')))
            {
                QString testPath = QString("%1:\\").arg(letter);
                UINT driveType = GetDriveTypeA(testPath.toLatin1().constData());
                if (driveType == DRIVE_REMOVABLE)
                {
                    // This is a removable drive - use it
                    // Note: This is a simplified check. Ideally we'd match by physical drive number.
                    drivePath = testPath;
                    qDebug() << "Found removable drive letter for physical drive:" << drivePath;
                    break;
                }
            }
        }

        if (drivePath.isEmpty())
        {
            qWarning() << "No drive letter found for physical device:" << device;
            return QString();
        }
    }
    else
    {
        drivePath = device;
        if (!drivePath.endsWith('\\'))
        {
            drivePath += "\\";
        }
    }

    char fsName[MAX_PATH + 1] = {0};
    char volumeName[MAX_PATH + 1] = {0};
    DWORD serialNumber = 0;
    DWORD maxComponentLen = 0;
    DWORD fsFlags = 0;

    if (GetVolumeInformationA(
            drivePath.toLatin1().constData(),
            volumeName, sizeof(volumeName),
            &serialNumber,
            &maxComponentLen,
            &fsFlags,
            fsName, sizeof(fsName)))
    {
        QString fsType = QString::fromLatin1(fsName).toLower();
        qDebug() << "Detected filesystem on" << drivePath << ":" << fsType;
        return fsType;
    }

    qWarning() << "Could not detect filesystem on:" << device;
    return QString();
}

bool isFat32(const QString &device)
{
    QString fsType = detectFilesystem(device);
    return fsType == "fat32" || fsType == "fat";
}

bool isCompatibleFilesystem(const QString &device)
{
    QString fsType = detectFilesystem(device).toLower();
    // FAT32, exFAT, and NTFS are all supported by the target Linux devices
    return fsType == "fat32" || fsType == "fat" || fsType == "exfat" || fsType == "ntfs";
}

} // namespace MountHelper
