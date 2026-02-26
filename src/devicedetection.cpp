/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "devicedetection.h"

namespace DeviceDetection {

DeviceType detectFromFilename(const QString &filename)
{
    QString lower = filename.toLower();

    // Check most specific patterns first, then broader ones

    // SimMan variants (must come before simpad to avoid false matches)
    if (lower.contains("simman3g-64") || lower.contains("simman-64"))
        return DeviceType::SimMan3G64;
    if (lower.contains("simman3g-32") || lower.contains("simman-32"))
        return DeviceType::SimMan3G32;
    if (lower.contains("simman3g") || lower.contains("simman"))
        return DeviceType::SimMan3G;

    // Explicit peripheral device names (must come before simpad pattern matching)
    if (lower.contains("linkbox2"))
        return DeviceType::LinkBox2;
    if (lower.contains("linkbox"))
        return DeviceType::LinkBox;
    if (lower.contains("cancpu2"))
        return DeviceType::CANCPU2;
    if (lower.contains("cancpu"))
        return DeviceType::CANCPU;

    // SimPad Plus 2 / imx8 (check before SimPad Plus to avoid "simpad" matching first)
    if (lower.contains("imx8") || lower.contains("simpad-plus2")
        || lower.contains("simpad_plus2") || lower.contains("simpad plus 2")
        || lower.contains("simpadplus2") || lower.contains("simpad2"))
        return DeviceType::SimPadPlus2;

    // SimPad Plus / imx6
    if (lower.contains("imx6") || lower.contains("simpad-plus")
        || lower.contains("simpad_plus") || lower.contains("simpad plus")
        || lower.contains("simpadplus") || lower.contains("simpad"))
        return DeviceType::SimPadPlus;

    return DeviceType::Unknown;
}

DeviceType detectFromCdnType(const QString &simpadType)
{
    QString type = simpadType.toLower();

    if (type == "plus" || type == "imx6")
        return DeviceType::SimPadPlus;
    if (type == "plus2" || type == "imx8")
        return DeviceType::SimPadPlus2;
    if (type.contains("simman") && type.contains("32"))
        return DeviceType::SimMan3G32;
    if (type.contains("simman") && type.contains("64"))
        return DeviceType::SimMan3G64;
    if (type.contains("simman"))
        return DeviceType::SimMan3G;
    if (type.contains("linkbox2"))
        return DeviceType::LinkBox2;
    if (type.contains("linkbox"))
        return DeviceType::LinkBox;
    if (type.contains("cancpu2"))
        return DeviceType::CANCPU2;
    if (type.contains("cancpu"))
        return DeviceType::CANCPU;

    return DeviceType::Unknown;
}

QJsonArray getDeviceTags(DeviceType type, bool isVsi)
{
    QJsonArray devices;

    switch (type) {
    case DeviceType::SimPadPlus:
        devices.append("imx6");
        if (!isVsi) {
            devices.append("linkbox");
            devices.append("cancpu");
        }
        break;
    case DeviceType::SimPadPlus2:
        devices.append("imx8");
        if (!isVsi) {
            devices.append("linkbox2");
            devices.append("cancpu2");
        }
        break;
    case DeviceType::SimMan3G32:
        devices.append("simman3g-32");
        break;
    case DeviceType::SimMan3G64:
        devices.append("simman3g-64");
        break;
    case DeviceType::SimMan3G:
        devices.append("simman3g");
        break;
    case DeviceType::LinkBox:
        devices.append("linkbox");
        break;
    case DeviceType::LinkBox2:
        devices.append("linkbox2");
        break;
    case DeviceType::CANCPU:
        devices.append("cancpu");
        break;
    case DeviceType::CANCPU2:
        devices.append("cancpu2");
        break;
    case DeviceType::Unknown:
        break;
    }

    return devices;
}

QString getDisplayName(DeviceType type)
{
    switch (type) {
    case DeviceType::SimPadPlus:    return QStringLiteral("SimPad Plus");
    case DeviceType::SimPadPlus2:   return QStringLiteral("SimPad Plus 2");
    case DeviceType::SimMan3G32:    return QStringLiteral("SimMan 3G (32-bit)");
    case DeviceType::SimMan3G64:    return QStringLiteral("SimMan 3G (64-bit)");
    case DeviceType::SimMan3G:      return QStringLiteral("SimMan 3G");
    case DeviceType::LinkBox:       return QStringLiteral("LinkBox");
    case DeviceType::LinkBox2:      return QStringLiteral("LinkBox 2");
    case DeviceType::CANCPU:        return QStringLiteral("CANCPU");
    case DeviceType::CANCPU2:       return QStringLiteral("CANCPU 2");
    case DeviceType::Unknown:       return QString();
    }
    return QString();
}

QString getIconPath(DeviceType type)
{
    switch (type) {
    case DeviceType::SimPadPlus:    return QStringLiteral("qrc:/qt/qml/RpiImager/icons/simpad_plus.png");
    case DeviceType::SimPadPlus2:   return QStringLiteral("qrc:/qt/qml/RpiImager/icons/simpad_plus2.png");
    case DeviceType::SimMan3G32:
    case DeviceType::SimMan3G64:
    case DeviceType::SimMan3G:      return QStringLiteral("qrc:/qt/qml/RpiImager/icons/simman3g.png");
    case DeviceType::LinkBox:       return QStringLiteral("qrc:/qt/qml/RpiImager/icons/linkbox.png");
    case DeviceType::LinkBox2:      return QStringLiteral("qrc:/qt/qml/RpiImager/icons/linkbox2.png");
    case DeviceType::CANCPU:        return QStringLiteral("qrc:/qt/qml/RpiImager/icons/cancpu.png");
    case DeviceType::CANCPU2:       return QStringLiteral("qrc:/qt/qml/RpiImager/icons/cancpu2.png");
    case DeviceType::Unknown:       return QStringLiteral("qrc:/qt/qml/RpiImager/icons/use_custom.png");
    }
    return QStringLiteral("qrc:/qt/qml/RpiImager/icons/use_custom.png");
}

bool isFileCompatibleWithDevice(const QString &filename, const QString &deviceTag)
{
    DeviceType fileType = detectFromFilename(filename);

    // Unknown device in file = generic/platform-independent, show to all
    if (fileType == DeviceType::Unknown)
        return true;

    // Get the tags this file would be tagged with (non-VSI, so cross-device tags included)
    QJsonArray fileTags = getDeviceTags(fileType, false);

    // Check if the selected device tag appears in this file's tags
    for (const auto &tag : fileTags) {
        if (tag.toString() == deviceTag)
            return true;
    }

    return false;
}

} // namespace DeviceDetection
