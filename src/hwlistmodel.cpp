/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

#include "hwlistmodel.h"
#include "imagewriter.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QJsonDocument>
#include <QDebug>
#include <QJsonValue>

// Returns static Laerdal device definitions
static QJsonArray getLaerdalDevices()
{
    static QJsonArray devices;
    if (devices.isEmpty()) {
        QJsonObject simpadPlus;
        simpadPlus["name"] = "SimPad Plus";
        simpadPlus["tags"] = QJsonArray({"imx6"});
        simpadPlus["capabilities"] = QJsonArray();
        simpadPlus["icon"] = "qrc:/qt/qml/RpiImager/icons/simpad_plus.png";
        simpadPlus["description"] = "i.MX6 based SimPad Plus device";
        simpadPlus["matching_type"] = "exclusive";
        simpadPlus["architecture"] = "armhf";
        simpadPlus["default"] = true;
        devices.append(simpadPlus);

        QJsonObject simpadPlus2;
        simpadPlus2["name"] = "SimPad Plus 2";
        simpadPlus2["tags"] = QJsonArray({"imx8"});
        simpadPlus2["capabilities"] = QJsonArray();
        simpadPlus2["icon"] = "qrc:/qt/qml/RpiImager/icons/simpad_plus2.png";
        simpadPlus2["description"] = "i.MX8 based SimPad Plus 2 device";
        simpadPlus2["matching_type"] = "exclusive";
        simpadPlus2["architecture"] = "aarch64";
        devices.append(simpadPlus2);

        QJsonObject simman3g32;
        simman3g32["name"] = "SimMan 3G (32-bit)";
        simman3g32["tags"] = QJsonArray({"simman3g-32"});
        simman3g32["capabilities"] = QJsonArray();
        simman3g32["icon"] = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
        simman3g32["description"] = "SimMan 3G 32-bit platform";
        simman3g32["matching_type"] = "exclusive";
        simman3g32["architecture"] = "armhf";
        devices.append(simman3g32);

        QJsonObject simman3g64;
        simman3g64["name"] = "SimMan 3G (64-bit)";
        simman3g64["tags"] = QJsonArray({"simman3g-64"});
        simman3g64["capabilities"] = QJsonArray();
        simman3g64["icon"] = "qrc:/qt/qml/RpiImager/icons/simman3g.png";
        simman3g64["description"] = "SimMan 3G 64-bit platform";
        simman3g64["matching_type"] = "exclusive";
        simman3g64["architecture"] = "aarch64";
        devices.append(simman3g64);
    }
    return devices;
}

HWListModel::HWListModel(ImageWriter &imageWriter)
    : QAbstractListModel(&imageWriter), _imageWriter(imageWriter) {}

bool HWListModel::reload()
{
    // Use static Laerdal device list instead of remote JSON
    const QJsonArray deviceArray = getLaerdalDevices();

    beginResetModel();
    _currentIndex = -1;
    // Replace contents on reload to avoid duplicate entries when re-entering the step
    _hwDevices.clear();
    _hwDevices.reserve(deviceArray.size());
    int indexOfDefault = -1;
    for (const QJsonValue &deviceValue: deviceArray) {
        QJsonObject deviceObj = deviceValue.toObject();

        HardwareDevice hwDevice = {
            deviceObj["name"].toString(),
            deviceObj["tags"].toArray(),
            deviceObj["capabilities"].toArray(),
            [&]() {
                QString iconPath = deviceObj["icon"].toString();
                // Adjust icon path for wizard directory structure
                if (iconPath.startsWith("icons/")) {
                    iconPath = "../" + iconPath;
                }
                // Route remote icons via image provider to avoid HTTP/2 errors
                if (iconPath.startsWith("http://") || iconPath.startsWith("https://")) {
                    iconPath = QStringLiteral("image://icons/") + iconPath;
                }
                return iconPath;
            }(),
            deviceObj["description"].toString(),
            deviceObj["matching_type"].toString(),
            deviceObj["architecture"].toString(),
            deviceObj["disabled"].toBool(false)
        };
        _hwDevices.append(hwDevice);

        if (deviceObj["default"].isBool() && deviceObj["default"].toBool())
            indexOfDefault = _hwDevices.size() - 1;
    }

    // Add "Use custom" option at the end - allows selecting a local WIC file
    HardwareDevice customDevice = {
        tr("Use custom"),
        QJsonArray(),  // Empty tags = no device filtering
        QJsonArray(),
        "qrc:/qt/qml/RpiImager/icons/use_custom.png",
        tr("Select a local .wic image file"),
        "inclusive",  // Show all OS images (no filtering)
        "",  // No architecture preference
        false  // Not disabled
    };
    _hwDevices.append(customDevice);

    endResetModel();

    setCurrentIndex(indexOfDefault);

    return true;
}

int HWListModel::rowCount(const QModelIndex &) const
{
    return _hwDevices.size();
}

QHash<int, QByteArray> HWListModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {TagsRole, "tags"},
        {CapabilitiesRole, "capabilities"},
        {IconRole, "icon"},
        {DescriptionRole, "description"},
        {MatchingTypeRole, "matching_type"},
        {ArchitectureRole, "architecture"},
        {DisabledRole, "disabled"}
    };
}

QVariant HWListModel::data(const QModelIndex &index, int role) const {
    const int row = index.row();
    if (row < 0 || row >= _hwDevices.size())
        return {};

    const HardwareDevice &device = _hwDevices[row];

    switch (HWListRole(role)) {
    case NameRole:
        return device.name;
    case TagsRole:
        return device.tags;
    case CapabilitiesRole:
        return device.capabilities;
    case IconRole:
        return device.icon;
    case DescriptionRole:
        return device.description;
    case MatchingTypeRole:
        return device.matchingType;
    case ArchitectureRole:
        return device.architecture;
    case DisabledRole:
        return device.disabled;
    }

    return {};
}

QString HWListModel::currentName() const {
    if (_currentIndex < 0 || _currentIndex >= _hwDevices.size())
        return tr("CHOOSE DEVICE");

    HardwareDevice device = _hwDevices[_currentIndex];
    return device.name;
}

QString HWListModel::currentArchitecture() const {
    if (_currentIndex < 0 || _currentIndex >= _hwDevices.size())
        return QString();

    HardwareDevice device = _hwDevices[_currentIndex];
    return device.architecture;
}

void HWListModel::setCurrentIndex(int index) {
    if (_currentIndex == index)
        return;

    // Allow -1 to clear the selection
    if (index < -1 || index >= _hwDevices.size()) {
        qWarning() << Q_FUNC_INFO << "Invalid index" << index;
        return;
    }

    // Handle clearing selection (index == -1)
    if (index == -1) {
        qDebug() << "Clearing hardware device selection";
        _currentIndex = -1;
        _lastSelectedDeviceName.clear();
        
        Q_EMIT currentIndexChanged();
        Q_EMIT currentNameChanged();
        Q_EMIT currentArchitectureChanged();
        return;
    }

    const HardwareDevice &device = _hwDevices.at(index);

    // Only clear image source if the device actually changed (not just re-selecting same device)
    bool deviceChanged = (_lastSelectedDeviceName != device.name);
    
    _imageWriter.setHWFilterList(device.tags, device.isInclusive());
    _imageWriter.setHWCapabilitiesList(device.capabilities);
    
    if (deviceChanged) {
        qDebug() << "Hardware device changed from" << _lastSelectedDeviceName << "to" << device.name << "- clearing image selection";
        _imageWriter.setSrc({});
        _lastSelectedDeviceName = device.name;
    } else {
        qDebug() << "Hardware device re-selected (" << device.name << ") - preserving image selection";
    }

    _currentIndex = index;

    Q_EMIT currentIndexChanged();
    Q_EMIT currentNameChanged();
    Q_EMIT currentArchitectureChanged();
}

int HWListModel::currentIndex() const {
    return _currentIndex;
}
