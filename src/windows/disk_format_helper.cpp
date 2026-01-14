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

    // Create diskpart script to clean, create partition, assign drive letter, and format
    // Using diskpart's format command with unit=32K bypasses Windows' 32GB FAT32 GUI limit
    // The key is using "format fs=fat32 unit=32K quick" directly in diskpart
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
    // Format with FAT32, 32KB allocation unit, and label - this bypasses the 32GB limit
    script << "format fs=fat32 unit=32K label=\"" << volumeLabel << "\" quick\r\n";
    script << "assign\r\n";
    scriptFile.close();

    // Run diskpart with the script
    qDebug() << "DiskFormatHelper: Running diskpart to prepare and format disk...";
    QProcess diskpartProc;
    diskpartProc.start("diskpart", {"/s", scriptPath});

    // Long timeout for large drives - format can take several minutes
    if (!diskpartProc.waitForFinished(600000))  // 10 minute timeout
    {
        QString diskpartError = QString::fromUtf8(diskpartProc.readAllStandardError());
        QString diskpartOut = QString::fromUtf8(diskpartProc.readAllStandardOutput());
        qWarning() << "DiskFormatHelper: diskpart timeout:" << diskpartError << diskpartOut;
        QFile::remove(scriptPath);
        result.errorMessage = QString("Format timeout - drive may be too slow or unresponsive");
        return result;
    }

    QString diskpartError = QString::fromUtf8(diskpartProc.readAllStandardError());
    QString diskpartOut = QString::fromUtf8(diskpartProc.readAllStandardOutput());

    QFile::remove(scriptPath);

    qDebug() << "DiskFormatHelper: diskpart output:" << diskpartOut;

    if (diskpartProc.exitCode() != 0)
    {
        qWarning() << "DiskFormatHelper: diskpart failed:" << diskpartError << diskpartOut;
        result.errorMessage = QString("Failed to format drive: %1").arg(diskpartError.isEmpty() ? diskpartOut : diskpartError);
        return result;
    }

    // Check if format actually succeeded by looking for success indicators in output
    // Diskpart returns 0 even if format fails in some cases
    if (diskpartOut.contains("DiskPart successfully formatted the volume", Qt::CaseInsensitive) ||
        diskpartOut.contains("successfully formatted", Qt::CaseInsensitive) ||
        diskpartOut.contains("formaterede", Qt::CaseInsensitive))  // Danish
    {
        qDebug() << "DiskFormatHelper: Format completed successfully";
    }
    else if (diskpartOut.contains("Virtual Disk Service error", Qt::CaseInsensitive) ||
             diskpartOut.contains("Virtuel disk", Qt::CaseInsensitive))  // Danish
    {
        qWarning() << "DiskFormatHelper: Virtual Disk Service error detected";
        result.errorMessage = QString("Failed to format drive: %1").arg(diskpartOut);
        return result;
    }

    // Wait for the device to be ready for I/O
    if (!PlatformQuirks::waitForDeviceReady(device, 5000)) {
        qWarning() << "DiskFormatHelper: Device may not be fully ready after format";
    }

    result.success = true;
    return result;
}

} // namespace DiskFormatHelper
