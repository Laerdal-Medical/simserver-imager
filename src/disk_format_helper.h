/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#ifndef DISK_FORMAT_HELPER_H
#define DISK_FORMAT_HELPER_H

#include <QString>

namespace DiskFormatHelper {

/**
 * @brief Result of a format operation
 */
struct FormatResult {
    bool success = false;
    QString errorMessage;
};

/**
 * @brief Format a device as FAT32 with a single partition
 * @param device The device path (e.g., "/dev/sdb" on Linux, "\\.\PhysicalDrive1" on Windows)
 * @param volumeLabel The volume label (max 11 characters for FAT32)
 * @return FormatResult with success status and error message if failed
 *
 * This function will:
 * 1. Unmount any existing partitions
 * 2. Create a new MBR partition table with a single partition
 * 3. Format the partition as FAT32
 *
 * Platform-specific implementations:
 * - Linux: Uses sfdisk + mkfs.fat (with pkexec if not root)
 * - macOS: Uses diskutil eraseDisk
 * - Windows: Uses diskpart
 */
FormatResult formatDeviceFat32(const QString &device, const QString &volumeLabel = "LAERDAL");

} // namespace DiskFormatHelper

#endif // DISK_FORMAT_HELPER_H
