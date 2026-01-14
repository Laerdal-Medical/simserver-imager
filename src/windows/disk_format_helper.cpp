/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "disk_format_helper.h"
#include "../platformquirks.h"

#include <QDebug>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>

namespace DiskFormatHelper {

FormatResult formatDeviceFat32(const QString &device, const QString &volumeLabel)
{
    FormatResult result;

    qDebug() << "DiskFormatHelper: Formatting device with diskpart:" << device;

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

    // Create diskpart script to clean, create partition, and assign drive letter
    // We'll format using PowerShell's Format-Volume which doesn't have the 32GB FAT32 limit
    QString scriptPath = QStandardPaths::writableLocation(QStandardPaths::TempLocation) + "/laerdal_diskpart.txt";
    QFile scriptFile(scriptPath);
    if (!scriptFile.open(QIODevice::WriteOnly | QIODevice::Text))
    {
        result.errorMessage = "Failed to create diskpart script";
        return result;
    }

    QTextStream script(&scriptFile);
    script << "select disk " << diskNumber << "\r\n";
    script << "clean\r\n";
    script << "create partition primary\r\n";
    script << "assign\r\n";  // Assign drive letter so we can format with PowerShell
    scriptFile.close();

    // Run diskpart with the script
    qDebug() << "DiskFormatHelper: Running diskpart to prepare disk...";
    QProcess diskpartProc;
    diskpartProc.start("diskpart", {"/s", scriptPath});

    if (!diskpartProc.waitForFinished(120000) || diskpartProc.exitCode() != 0)
    {
        QString diskpartError = QString::fromUtf8(diskpartProc.readAllStandardError());
        QString diskpartOut = QString::fromUtf8(diskpartProc.readAllStandardOutput());
        qWarning() << "DiskFormatHelper: diskpart failed:" << diskpartError << diskpartOut;
        QFile::remove(scriptPath);
        result.errorMessage = QString("Failed to prepare drive: %1").arg(diskpartError.isEmpty() ? diskpartOut : diskpartError);
        return result;
    }

    QFile::remove(scriptPath);
    qDebug() << "DiskFormatHelper: Diskpart completed, partition created";

    // Wait for Windows to assign a drive letter
    QThread::msleep(2000);

    // Find the drive letter that was assigned to our disk
    // Use PowerShell to get the drive letter for the physical disk
    qDebug() << "DiskFormatHelper: Finding assigned drive letter...";
    QProcess psGetDrive;
    QString psScript = QString(
        "Get-Partition -DiskNumber %1 | Where-Object { $_.DriveLetter } | "
        "Select-Object -ExpandProperty DriveLetter -First 1"
    ).arg(diskNumber);

    psGetDrive.start("powershell", {"-NoProfile", "-Command", psScript});
    if (!psGetDrive.waitForFinished(30000))
    {
        result.errorMessage = "Timeout waiting for drive letter assignment";
        return result;
    }

    QString driveLetter = QString::fromUtf8(psGetDrive.readAllStandardOutput()).trimmed();
    if (driveLetter.isEmpty())
    {
        result.errorMessage = "Could not find assigned drive letter";
        return result;
    }

    qDebug() << "DiskFormatHelper: Drive letter assigned:" << driveLetter;

    // Format using PowerShell's Format-Volume which doesn't have the 32GB FAT32 limitation
    // This is the key to bypassing Windows' artificial limit
    qDebug() << "DiskFormatHelper: Formatting with PowerShell Format-Volume...";
    QProcess psFormat;
    QString formatScript = QString(
        "Format-Volume -DriveLetter %1 -FileSystem FAT32 -NewFileSystemLabel '%2' -AllocationUnitSize 32768 -Force -Confirm:$false"
    ).arg(driveLetter, volumeLabel);

    psFormat.start("powershell", {"-NoProfile", "-Command", formatScript});
    if (!psFormat.waitForFinished(300000))  // 5 minute timeout for large drives
    {
        QString psError = QString::fromUtf8(psFormat.readAllStandardError());
        result.errorMessage = QString("Format timeout: %1").arg(psError);
        return result;
    }

    if (psFormat.exitCode() != 0)
    {
        QString psError = QString::fromUtf8(psFormat.readAllStandardError());
        QString psOut = QString::fromUtf8(psFormat.readAllStandardOutput());
        qWarning() << "DiskFormatHelper: PowerShell format failed:" << psError << psOut;
        result.errorMessage = QString("Failed to format drive: %1").arg(psError.isEmpty() ? psOut : psError);
        return result;
    }

    qDebug() << "DiskFormatHelper: Format completed successfully";

    // Wait for the device to be ready for I/O
    if (!PlatformQuirks::waitForDeviceReady(device, 5000)) {
        qWarning() << "DiskFormatHelper: Device may not be fully ready after format";
    }

    result.success = true;
    return result;
}

} // namespace DiskFormatHelper
