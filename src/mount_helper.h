/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

#ifndef MOUNT_HELPER_H
#define MOUNT_HELPER_H

#include <QString>

namespace MountHelper {

/**
 * @brief Mount a device partition to a temporary mount point
 * @param device The device path (e.g., "/dev/sdb" on Linux)
 * @return The mount point path on success, empty string on failure
 *
 * This function will:
 * 1. Wait for the first partition to appear (device + "1")
 * 2. Create a temporary mount point
 * 3. Mount the partition
 */
QString mountDevice(const QString &device);

/**
 * @brief Unmount a device and clean up the mount point
 * @param mountPoint The path returned by mountDevice()
 * @return true on success, false on failure
 *
 * This function will:
 * 1. Sync the filesystem
 * 2. Unmount the partition
 * 3. Remove the temporary mount point directory
 */
bool unmountDevice(const QString &mountPoint);

/**
 * @brief Wait for a partition to appear after formatting
 * @param device The base device path (e.g., "/dev/sdb")
 * @param timeoutMs Maximum time to wait in milliseconds
 * @return The partition path if found, empty string on timeout
 */
QString waitForPartition(const QString &device, int timeoutMs = 10000);

/**
 * @brief Detect the filesystem type of a device or partition
 * @param device The device or partition path
 * @return Filesystem type string (e.g., "vfat", "ntfs", "ext4"), empty on error
 */
QString detectFilesystem(const QString &device);

/**
 * @brief Check if a device has a FAT32 filesystem
 * @param device The device or partition path
 * @return true if the filesystem is FAT32 (vfat), false otherwise
 */
bool isFat32(const QString &device);

} // namespace MountHelper

#endif // MOUNT_HELPER_H
