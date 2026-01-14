/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "disk_format_helper.h"
#include "../platformquirks.h"
#include "../disk_formatter.h"

#include <QDebug>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>
#include <QThread>
#include <QDateTime>

#include <windows.h>
#include <winioctl.h>

namespace DiskFormatHelper {

// Helper to force Windows to rescan a disk's partition table
static bool rescanDisk(const QString &device)
{
    // Open the physical drive
    HANDLE hDevice = CreateFileW(
        reinterpret_cast<LPCWSTR>(device.utf16()),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );

    if (hDevice == INVALID_HANDLE_VALUE) {
        qWarning() << "DiskFormatHelper: Failed to open device for rescan:" << GetLastError();
        return false;
    }

    // Force Windows to re-read the partition table
    DWORD bytesReturned;
    BOOL result = DeviceIoControl(
        hDevice,
        IOCTL_DISK_UPDATE_PROPERTIES,
        nullptr, 0,
        nullptr, 0,
        &bytesReturned,
        nullptr
    );

    CloseHandle(hDevice);

    if (!result) {
        qWarning() << "DiskFormatHelper: IOCTL_DISK_UPDATE_PROPERTIES failed:" << GetLastError();
        return false;
    }

    return true;
}

FormatResult formatDeviceFat32(const QString &device, const QString &volumeLabel)
{
    FormatResult result;

    qDebug() << "DiskFormatHelper: Formatting device with DiskFormatter:" << device;

    // Extract disk number from device path (e.g., "\\.\PhysicalDrive1" -> "1")
    QString diskNumber;
    QRegularExpression diskRe("PhysicalDrive(\\d+)");
    QRegularExpressionMatch match = diskRe.match(device);
    if (match.hasMatch())
    {
        diskNumber = match.captured(1);
    }
    else
    {
        result.errorMessage = QString("Could not determine disk number from device path: %1").arg(device);
        return result;
    }

    // Step 1: Use diskpart to clean the disk and remove all existing partitions/volumes
    // This is necessary so DiskFormatter can write directly to the raw disk
    QString scriptPath = QStandardPaths::writableLocation(QStandardPaths::TempLocation) + "/laerdal_diskpart.txt";
    QFile scriptFile(scriptPath);
    if (!scriptFile.open(QIODevice::WriteOnly | QIODevice::Text))
    {
        result.errorMessage = "Failed to create diskpart script";
        return result;
    }

    QTextStream script(&scriptFile);
    script << "select disk " << diskNumber << "\r\n";
    script << "clean\r\n";  // Remove all partitions
    scriptFile.close();

    qDebug() << "DiskFormatHelper: Running diskpart to clean disk...";
    QProcess diskpartProc;
    diskpartProc.start("diskpart", {"/s", scriptPath});

    if (!diskpartProc.waitForFinished(120000))
    {
        QFile::remove(scriptPath);
        result.errorMessage = "Timeout cleaning drive";
        return result;
    }

    QString diskpartOut = QString::fromUtf8(diskpartProc.readAllStandardOutput());
    QFile::remove(scriptPath);

    qDebug() << "DiskFormatHelper: diskpart output:" << diskpartOut;

    if (diskpartProc.exitCode() != 0)
    {
        QString diskpartError = QString::fromUtf8(diskpartProc.readAllStandardError());
        result.errorMessage = QString("Failed to clean drive: %1").arg(diskpartError.isEmpty() ? diskpartOut : diskpartError);
        return result;
    }

    // Wait for Windows to process the clean operation
    QThread::msleep(2000);

    // Step 2: Use DiskFormatter to write MBR and FAT32 filesystem directly
    // This bypasses Windows' 32GB FAT32 limit by writing raw disk structures
    qDebug() << "DiskFormatHelper: Writing FAT32 filesystem with DiskFormatter...";

    // Create DiskFormatter with custom volume label and unique volume ID
    rpi_imager::DiskFormatter formatter;

    // Convert device path for DiskFormatter (it expects "\\\\.\\PhysicalDriveN" format)
    std::string devicePath = device.toStdString();

    auto formatResult = formatter.FormatDrive(devicePath);
    if (!formatResult) {
        qWarning() << "DiskFormatHelper: DiskFormatter failed with error:" << static_cast<int>(formatResult.error());
        result.errorMessage = "Failed to write FAT32 filesystem to drive";
        return result;
    }

    qDebug() << "DiskFormatHelper: DiskFormatter completed, rescanning disk...";

    // Step 3: Force Windows to rescan the disk and recognize the new partition table
    QThread::msleep(1000);

    if (!rescanDisk(device)) {
        qWarning() << "DiskFormatHelper: Disk rescan failed, trying diskpart rescan...";
    }

    // Also use diskpart to rescan all disks
    QFile scriptFile2(scriptPath);
    if (scriptFile2.open(QIODevice::WriteOnly | QIODevice::Text))
    {
        QTextStream script2(&scriptFile2);
        script2 << "rescan\r\n";
        scriptFile2.close();

        QProcess rescanProc;
        rescanProc.start("diskpart", {"/s", scriptPath});
        rescanProc.waitForFinished(30000);
        QFile::remove(scriptPath);
    }

    // Wait for Windows to recognize the new filesystem
    QThread::msleep(3000);

    // Step 4: Find the partition and assign a drive letter
    qDebug() << "DiskFormatHelper: Assigning drive letter...";

    QFile scriptFile3(scriptPath);
    if (!scriptFile3.open(QIODevice::WriteOnly | QIODevice::Text))
    {
        // Non-fatal - drive letter may auto-assign
        qWarning() << "DiskFormatHelper: Could not create script for drive letter assignment";
    }
    else
    {
        QTextStream script3(&scriptFile3);
        script3 << "select disk " << diskNumber << "\r\n";
        script3 << "select partition 1\r\n";
        script3 << "assign\r\n";
        scriptFile3.close();

        QProcess assignProc;
        assignProc.start("diskpart", {"/s", scriptPath});
        assignProc.waitForFinished(30000);
        QFile::remove(scriptPath);

        qDebug() << "DiskFormatHelper: Drive letter assignment output:"
                 << QString::fromUtf8(assignProc.readAllStandardOutput());
    }

    // Wait for the device to be ready for I/O
    QThread::msleep(2000);

    if (!PlatformQuirks::waitForDeviceReady(device, 5000)) {
        qWarning() << "DiskFormatHelper: Device may not be fully ready after format";
    }

    qDebug() << "DiskFormatHelper: Format completed successfully";
    result.success = true;
    return result;
}

} // namespace DiskFormatHelper
