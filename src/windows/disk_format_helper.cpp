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
#include <QThread>

namespace DiskFormatHelper {

FormatResult formatDeviceFat32(const QString &device, const QString &volumeLabel)
{
    FormatResult result;

    qDebug() << "DiskFormatHelper: Formatting device:" << device;

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

    // Step 1: Use diskpart to clean disk, create partition, and assign drive letter
    // We DON'T format with diskpart because it has the 32GB FAT32 limit
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
    script << "select partition 1\r\n";
    script << "active\r\n";
    script << "assign\r\n";  // Assign drive letter - we'll format separately
    scriptFile.close();

    qDebug() << "DiskFormatHelper: Running diskpart to prepare disk...";
    QProcess diskpartProc;
    diskpartProc.start("diskpart", {"/s", scriptPath});

    if (!diskpartProc.waitForFinished(120000))
    {
        QFile::remove(scriptPath);
        result.errorMessage = "Timeout preparing drive";
        return result;
    }

    QString diskpartOut = QString::fromUtf8(diskpartProc.readAllStandardOutput());
    QFile::remove(scriptPath);

    qDebug() << "DiskFormatHelper: diskpart output:" << diskpartOut;

    if (diskpartProc.exitCode() != 0)
    {
        QString diskpartError = QString::fromUtf8(diskpartProc.readAllStandardError());
        result.errorMessage = QString("Failed to prepare drive: %1").arg(diskpartError.isEmpty() ? diskpartOut : diskpartError);
        return result;
    }

    // Wait for Windows to assign a drive letter
    QThread::msleep(3000);

    // Step 2: Find the drive letter that was assigned
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

    // Step 3: Format using format.com with /FS:FAT32 /A:32K
    // The Windows format.com command CAN format >32GB as FAT32 when called directly
    // The 32GB limit is only in the GUI and diskpart's format command
    qDebug() << "DiskFormatHelper: Formatting with format.com...";
    QProcess formatProc;

    // format.com requires /Y for non-interactive and /Q for quick format
    // /A:32K sets 32KB allocation unit size for large drives
    // /V: sets the volume label
    QString formatCmd = QString("format %1: /FS:FAT32 /A:32K /V:%2 /Q /Y")
        .arg(driveLetter, volumeLabel);

    formatProc.start("cmd", {"/c", formatCmd});

    if (!formatProc.waitForFinished(600000))  // 10 minute timeout for large drives
    {
        QString formatError = QString::fromUtf8(formatProc.readAllStandardError());
        result.errorMessage = QString("Format timeout: %1").arg(formatError);
        return result;
    }

    QString formatOut = QString::fromUtf8(formatProc.readAllStandardOutput());
    QString formatErr = QString::fromUtf8(formatProc.readAllStandardError());

    qDebug() << "DiskFormatHelper: format.com output:" << formatOut;
    if (!formatErr.isEmpty()) {
        qDebug() << "DiskFormatHelper: format.com stderr:" << formatErr;
    }

    if (formatProc.exitCode() != 0)
    {
        qWarning() << "DiskFormatHelper: format.com failed with exit code:" << formatProc.exitCode();
        result.errorMessage = QString("Failed to format drive: %1").arg(formatErr.isEmpty() ? formatOut : formatErr);
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
