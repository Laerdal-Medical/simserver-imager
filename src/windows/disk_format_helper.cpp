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

    // Create diskpart script
    // Using unit=32768 (32KB clusters) bypasses Windows' 32GB FAT32 limit.
    // FAT32 with 32KB clusters supports volumes up to 2TB.
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
    script << "format fs=fat32 quick unit=32768 label=" << volumeLabel << "\r\n";
    script << "assign\r\n";
    scriptFile.close();

    // Run diskpart with the script
    QProcess diskpartProc;
    diskpartProc.start("diskpart", {"/s", scriptPath});

    if (!diskpartProc.waitForFinished(120000) || diskpartProc.exitCode() != 0)
    {
        QString diskpartError = QString::fromUtf8(diskpartProc.readAllStandardError());
        QString diskpartOut = QString::fromUtf8(diskpartProc.readAllStandardOutput());
        qWarning() << "DiskFormatHelper: diskpart failed:" << diskpartError << diskpartOut;
        QFile::remove(scriptPath);
        result.errorMessage = QString("Failed to format drive: %1").arg(diskpartError.isEmpty() ? diskpartOut : diskpartError);
        return result;
    }

    QFile::remove(scriptPath);
    qDebug() << "DiskFormatHelper: Format completed successfully";

    // Wait for the device to be ready for I/O
    if (!PlatformQuirks::waitForDeviceReady(device, 5000)) {
        qWarning() << "DiskFormatHelper: Device may not be fully ready after format";
    }

    result.success = true;
    return result;
}

} // namespace DiskFormatHelper
