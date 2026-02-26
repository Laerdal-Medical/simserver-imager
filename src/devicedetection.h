/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#ifndef DEVICEDETECTION_H
#define DEVICEDETECTION_H

#include <QString>
#include <QJsonArray>

/**
 * @brief Centralized device detection utilities
 *
 * Single source of truth for mapping file names, CDN types, and other text
 * to device types, tags, display names, and icons. Used by RepositoryManager,
 * LaerdalCdnSource, and ImageWriter.
 */
namespace DeviceDetection {

enum class DeviceType {
    Unknown,
    SimPadPlus,     // imx6
    SimPadPlus2,    // imx8
    SimMan3G32,     // 32-bit SimMan 3G
    SimMan3G64,     // 64-bit SimMan 3G
    SimMan3G,       // generic SimMan 3G (no bitness)
    LinkBox,
    LinkBox2,
    CANCPU,
    CANCPU2
};

/**
 * @brief Detect device type from a filename or artifact name
 *
 * Uses contains-based matching, checking most specific patterns first.
 * E.g., "simpad-plus2" → SimPadPlus2, "simman3g-64" → SimMan3G64
 */
DeviceType detectFromFilename(const QString &filename);

/**
 * @brief Detect device type from a structured Laerdal CDN simpadType value
 *
 * Uses equality-based matching for canonical CDN values like "plus", "plus2", "imx6".
 */
DeviceType detectFromCdnType(const QString &simpadType);

/**
 * @brief Get device tags for hardware filtering
 *
 * Returns the primary tag plus cross-device compatible tags.
 * SimPad Plus (imx6) WIC images also work on LinkBox and CANCPU.
 * SimPad Plus 2 (imx8) WIC images also work on LinkBox2 and CANCPU2.
 * VSI files are device-specific and skip cross-device tags.
 *
 * @param type The detected device type
 * @param isVsi Whether the image is a VSI file (skips cross-device tags)
 */
QJsonArray getDeviceTags(DeviceType type, bool isVsi = false);

/**
 * @brief Get human-readable display name
 *
 * E.g., SimPadPlus → "SimPad Plus", SimMan3G64 → "SimMan 3G (64-bit)"
 */
QString getDisplayName(DeviceType type);

/**
 * @brief Get icon resource path for a device type
 *
 * Returns a qrc:// path to the appropriate device icon.
 */
QString getIconPath(DeviceType type);

/**
 * @brief Check if a file is compatible with a selected device
 *
 * Detects the device type from the filename, then checks if that device's
 * tags overlap with the selected device's compatible tags.
 * Files with no detectable device are considered generic (compatible with all).
 *
 * @param filename The file/asset name to check
 * @param deviceTag The hardware filter tag of the selected device (e.g., "cancpu", "imx6")
 * @return true if the file should be shown for the selected device
 */
bool isFileCompatibleWithDevice(const QString &filename, const QString &deviceTag);

} // namespace DeviceDetection

#endif // DEVICEDETECTION_H
