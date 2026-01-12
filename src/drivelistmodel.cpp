/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

#include "drivelistmodel.h"
#include "config.h"
#include "dependencies/drivelist/src/drivelist.hpp"
#include <QSet>
#include <QDebug>

DriveListModel::DriveListModel(QObject *parent)
    : QAbstractListModel(parent)
{
    _rolenames = {
        {deviceRole, "device"},
        {descriptionRole, "description"},
        {sizeRole, "size"},
        {isUsbRole, "isUsb"},
        {isScsiRole, "isScsi"},
        {isReadOnlyRole, "isReadOnly"},
        {isSystemRole, "isSystem"},
        {mountpointsRole, "mountpoints"},
        {childDevicesRole, "childDevices"}
    };

    // Enumerate drives in seperate thread, but process results in UI thread
    connect(&_thread, SIGNAL(newDriveList(std::vector<Drivelist::DeviceDescriptor>)), SLOT(processDriveList(std::vector<Drivelist::DeviceDescriptor>)));
    
    // Forward performance event signal
    connect(&_thread, &DriveListModelPollThread::eventDriveListPoll,
            this, &DriveListModel::eventDriveListPoll);
}

int DriveListModel::rowCount(const QModelIndex &) const
{
    return _drivelist.count();
}

QHash<int, QByteArray> DriveListModel::roleNames() const
{
    return _rolenames;
}

QVariant DriveListModel::data(const QModelIndex &index, int role) const
{
    int row = index.row();
    if (row < 0 || row >= _drivelist.count())
        return QVariant();

    QByteArray propertyName = _rolenames.value(role);
    if (propertyName.isEmpty())
        return QVariant();
    else {
        auto it = _drivelist.cbegin();
        std::advance(it, row);
        return it.value()->property(propertyName);
    }
}

void DriveListModel::processDriveList(std::vector<Drivelist::DeviceDescriptor> l)
{
    QSet<QString> drivesInNewList;

    // First pass: collect all valid drives from the new list
    struct NewDriveInfo {
        QString key;
        QString device;
        QString description;
        quint64 size;
        bool isUSB;
        bool isScsi;
        bool isReadOnly;
        bool isSystem;
        QStringList mountpoints;
        QStringList childDevices;
    };
    QList<NewDriveInfo> drivesToAdd;
    QList<NewDriveInfo> drivesToUpdate;

    for (auto &i: l)
    {
        // Convert STL vector<string> to Qt QStringList
        QStringList mountpoints;
        for (auto &s: i.mountpoints)
        {
            mountpoints.append(QString::fromStdString(s));
        }

        // Should already be caught by isSystem variable, but just in case...
        if (mountpoints.contains("/") || mountpoints.contains("C://"))
            continue;

        // Skip zero-sized devices
        if (i.size == 0)
            continue;

        // Allow read/write virtual devices (mounted disk images) but filter out:
        // - Read-only virtual devices
        // - System virtual devices (like APFS volumes on macOS)
        // - Virtual devices that are not removable/ejectable (likely system virtual devices)
        if (i.isVirtual && (i.isReadOnly || i.isSystem || !i.isRemovable))
            continue;

        QString deviceNamePlusSize = QString::fromStdString(i.device)+":"+QString::number(i.size);
        if (i.isReadOnly)
            deviceNamePlusSize += "ro";
        drivesInNewList.insert(deviceNamePlusSize);

        // Mark virtual disks as system drives to trigger confirmation dialog
        const bool isSystemOverride = i.isSystem || i.isVirtual;

        // Treat NVMe drives like SCSI for icon purposes
        QString busType = QString::fromStdString(i.busType);
        QString devicePath = QString::fromStdString(i.device);
        bool isNvme = (busType.compare("NVME", Qt::CaseInsensitive) == 0) || devicePath.startsWith("/dev/nvme");
        bool isScsiForIcon = i.isSCSI || isNvme;

        // Convert child devices (APFS volumes on macOS) to QStringList
        QStringList childDevices;
        for (auto &s: i.childDevices)
        {
            childDevices.append(QString::fromStdString(s));
        }

        NewDriveInfo info;
        info.key = deviceNamePlusSize;
        info.device = QString::fromStdString(i.device);
        info.description = QString::fromStdString(i.description);
        info.size = i.size;
        info.isUSB = i.isUSB;
        info.isScsi = isScsiForIcon;
        info.isReadOnly = i.isReadOnly;
        info.isSystem = isSystemOverride;
        info.mountpoints = mountpoints;
        info.childDevices = childDevices;

        if (!_drivelist.contains(deviceNamePlusSize))
        {
            // New drive - add it
            drivesToAdd.append(info);
        }
        else
        {
            // Existing drive - check if properties changed (description, mountpoints, etc.)
            DriveListItem *existing = _drivelist.value(deviceNamePlusSize);
            if (existing->property("description").toString() != info.description ||
                existing->property("mountpoints").toStringList() != info.mountpoints ||
                existing->property("childDevices").toStringList() != info.childDevices)
            {
                // Properties changed - need to update (replace) the item
                drivesToUpdate.append(info);
            }
        }
    }

    // Remove drives that are no longer present (iterate in reverse to maintain valid indices)
    QStringList drivesInOldList = _drivelist.keys();
    for (int i = drivesInOldList.size() - 1; i >= 0; --i)
    {
        const QString &key = drivesInOldList.at(i);
        if (!drivesInNewList.contains(key))
        {
            // Find the row index for this key
            int row = _drivelist.keys().indexOf(key);
            if (row >= 0)
            {
                QString devicePath = _drivelist.value(key)->property("device").toString();
                qDebug() << "Drive removed:" << devicePath;

                beginRemoveRows(QModelIndex(), row, row);
                _drivelist.value(key)->deleteLater();
                _drivelist.remove(key);
                endRemoveRows();

                // Emit signal for this specific device removal
                emit deviceRemoved(devicePath);
            }
        }
    }

    // Update existing drives with changed properties
    // Since DriveListItem properties are CONSTANT, we need to replace the item
    for (const auto &info : drivesToUpdate)
    {
        int row = _drivelist.keys().indexOf(info.key);
        if (row >= 0)
        {
            qDebug() << "Drive updated:" << info.device << "description:" << info.description;

            // Delete old item and create new one with updated properties
            _drivelist.value(info.key)->deleteLater();
            _drivelist[info.key] = new DriveListItem(
                info.device, info.description, info.size,
                info.isUSB, info.isScsi, info.isReadOnly, info.isSystem,
                info.mountpoints, info.childDevices, this);

            // Notify view that this row's data changed
            QModelIndex idx = index(row);
            emit dataChanged(idx, idx);
        }
    }

    // Add new drives
    for (const auto &info : drivesToAdd)
    {
        // Calculate the row index where this key will be inserted
        // QMap is sorted, so we need to find where this key fits
        int row = 0;
        for (auto it = _drivelist.constBegin(); it != _drivelist.constEnd(); ++it)
        {
            if (it.key() >= info.key)
                break;
            ++row;
        }

        beginInsertRows(QModelIndex(), row, row);
        _drivelist[info.key] = new DriveListItem(
            info.device, info.description, info.size,
            info.isUSB, info.isScsi, info.isReadOnly, info.isSystem,
            info.mountpoints, info.childDevices, this);
        endInsertRows();

        qDebug() << "Drive added:" << info.device;
    }
}

void DriveListModel::startPolling()
{
    _thread.start();
}

void DriveListModel::stopPolling()
{
    _thread.stop();
}

void DriveListModel::pausePolling()
{
    _thread.pause();
}

void DriveListModel::resumePolling()
{
    _thread.resume();
}

void DriveListModel::setSlowPolling()
{
    _thread.setScanMode(DriveListModelPollThread::ScanMode::Slow);
}

void DriveListModel::refreshNow()
{
    _thread.refreshNow();
}

QStringList DriveListModel::getChildDevices(const QString &device) const
{
    // Search through cached drive list for matching device
    for (auto it = _drivelist.cbegin(); it != _drivelist.cend(); ++it)
    {
        DriveListItem *item = it.value();
        if (item && item->property("device").toString() == device)
        {
            return item->property("childDevices").toStringList();
        }
    }
    return QStringList();
}