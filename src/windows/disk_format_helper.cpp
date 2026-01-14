/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#include "disk_format_helper.h"
#include "../disk_formatter.h"
#include "../platformquirks.h"
#include "diskpart_util.h"

#include <QDebug>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>

#include <chrono>

namespace DiskFormatHelper {

FormatResult formatDeviceFat32(const QString &device, const QString &volumeLabel)
{
    Q_UNUSED(volumeLabel); // Volume label is set by DiskFormatter
    FormatResult result;

    qDebug() << "DiskFormatHelper: Formatting device:" << device;

    // Step 1: Clean the disk using diskpart (removes partitions, prepares for formatting)
    // This is necessary because Windows needs the disk to be cleaned before we can write to it directly.
    // Using the standard 60s timeout with 3 retries and unmount-first behavior.
    qDebug() << "DiskFormatHelper: Cleaning disk with diskpart...";
    auto diskpartResult = DiskpartUtil::cleanDisk(device.toLatin1(), std::chrono::seconds(60), 3, DiskpartUtil::VolumeHandling::UnmountFirst);
    if (!diskpartResult.success)
    {
        result.errorMessage = QString("Failed to clean disk: %1").arg(diskpartResult.errorMessage);
        return result;
    }

    // Step 2: Use cross-platform DiskFormatter to write FAT32 directly
    // This bypasses Windows' 32GB FAT32 limitation by writing the filesystem structures
    // at the byte level, rather than using Windows format APIs.
    qDebug() << "DiskFormatHelper: Writing FAT32 filesystem with DiskFormatter...";
    rpi_imager::DiskFormatter formatter;
    auto formatResult = formatter.FormatDrive(device.toStdString());

    if (!formatResult)
    {
        QString errorMsg;
        switch (formatResult.error()) {
            case rpi_imager::FormatError::kFileOpenError:
                errorMsg = "Error opening device for formatting";
                break;
            case rpi_imager::FormatError::kFileWriteError:
                errorMsg = "Error writing to device during formatting";
                break;
            case rpi_imager::FormatError::kFileSeekError:
                errorMsg = "Error seeking on device during formatting";
                break;
            case rpi_imager::FormatError::kInvalidParameters:
                errorMsg = "Invalid parameters for formatting";
                break;
            case rpi_imager::FormatError::kInsufficientSpace:
                errorMsg = "Insufficient space on device";
                break;
            default:
                errorMsg = "Unknown formatting error";
                break;
        }
        result.errorMessage = errorMsg;
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
