/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

#include "driveformatthread.h"
#include "disk_format_helper.h"
#include <QDebug>
#include <QElapsedTimer>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

DriveFormatThread::DriveFormatThread(const QByteArray &device, QObject *parent)
    : QThread(parent), _device(device)
{

}

DriveFormatThread::~DriveFormatThread()
{
    wait();
}

void DriveFormatThread::run()
{
#ifdef Q_OS_WIN
    // Suppress Windows "Insert a disk" / "not accessible" system error dialogs
    // for this thread. Error mode is per-thread, so we set it once at thread start.
    DWORD oldMode;
    if (!SetThreadErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX, &oldMode)) {
        SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
    }
#endif

    qDebug() << "Formatting device" << _device;
    emit preparationStatusUpdate(tr("Formatting drive as FAT32..."));

    QElapsedTimer formatTimer;
    formatTimer.start();

    // Use platform-specific DiskFormatHelper which:
    // - Linux: Uses sfdisk + mkfs.fat (native tools)
    // - Windows: Uses diskpart + PowerShell Format-Volume (bypasses 32GB FAT32 limit)
    // - macOS: Uses diskutil eraseDisk
    QString device = QString::fromLatin1(_device);
    auto result = DiskFormatHelper::formatDeviceFat32(device, "LAERDAL");

    quint32 formatDurationMs = static_cast<quint32>(formatTimer.elapsed());

    if (!result.success) {
        emit eventDriveFormat(formatDurationMs, false);
        emit error(result.errorMessage);
    } else {
        emit eventDriveFormat(formatDurationMs, true);
        qDebug() << "Format succeeded in" << formatDurationMs << "ms";
        emit success();
    }
}
