#include "drivelistmodelpollthread.h"
#include <QElapsedTimer>
#include <QDebug>
#ifdef Q_OS_WIN
#include <windows.h>
#endif

/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

DriveListModelPollThread::DriveListModelPollThread(QObject *parent)
    : QThread(parent)
{
    qRegisterMetaType< std::vector<Drivelist::DeviceDescriptor> >( "std::vector<Drivelist::DeviceDescriptor>" );
}

DriveListModelPollThread::~DriveListModelPollThread()
{
    _terminate = true;
    _modeChanged.wakeAll();  // Wake thread if it's waiting
    if (!wait(2000)) {
        terminate();
    }
}

void DriveListModelPollThread::stop()
{
    _terminate = true;
    _modeChanged.wakeAll();  // Wake thread to check terminate flag
}

void DriveListModelPollThread::start()
{
    _terminate = false;
    QThread::start();
}

void DriveListModelPollThread::setScanMode(ScanMode mode)
{
    QMutexLocker lock(&_mutex);
    if (_scanMode != mode) {
        ScanMode oldMode = _scanMode;
        _scanMode = mode;
        
        const char* modeStr = (mode == ScanMode::Normal) ? "Normal" :
                              (mode == ScanMode::Slow) ? "Slow" : "Paused";
        qDebug() << "Drive scan mode changed to:" << modeStr;
        
        // Wake thread if transitioning from paused to active
        if (oldMode == ScanMode::Paused && mode != ScanMode::Paused) {
            _modeChanged.wakeAll();
        }
        
        emit scanModeChanged(mode);
    }
}

DriveListModelPollThread::ScanMode DriveListModelPollThread::scanMode() const
{
    QMutexLocker lock(&_mutex);
    return _scanMode;
}

void DriveListModelPollThread::pause()
{
    setScanMode(ScanMode::Paused);
}

void DriveListModelPollThread::resume()
{
    setScanMode(ScanMode::Normal);
}

void DriveListModelPollThread::refreshNow()
{
    QMutexLocker lock(&_mutex);
    _refreshRequested = true;
    qDebug() << "Drive list refresh requested";
    _modeChanged.wakeAll();  // Wake thread to perform immediate scan
}

void DriveListModelPollThread::run()
{
#ifdef Q_OS_WIN
    // Suppress Windows "Insert a disk" / "not accessible" system error dialogs
    // for this thread. Error mode is per-thread, so we set it once at thread start.
    DWORD oldMode;
    if (!SetThreadErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX, &oldMode)) {
        SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
    }
#endif

    QElapsedTimer t1;

    while (!_terminate)
    {
        // Check current scan mode and refresh flag
        ScanMode currentMode;
        bool needsRefresh;
        {
            QMutexLocker lock(&_mutex);
            currentMode = _scanMode;
            needsRefresh = _refreshRequested;
            _refreshRequested = false;  // Clear the flag
        }

        if (currentMode == ScanMode::Paused && !needsRefresh) {
            // Wait until mode changes, refresh requested, or we're told to terminate
            QMutexLocker lock(&_mutex);
            while (_scanMode == ScanMode::Paused && !_refreshRequested && !_terminate) {
                _modeChanged.wait(&_mutex, 500);  // Check every 500ms for terminate
            }
            continue;  // Re-check mode after waking
        }

        // Perform the scan
        t1.start();
        emit newDriveList( Drivelist::ListStorageDevices() );
        quint32 elapsed = static_cast<quint32>(t1.elapsed());

        // Emit timing event for performance tracking (always, but listeners can filter)
        emit eventDriveListPoll(elapsed);

        if (elapsed > 1000)
            qDebug() << "Enumerating drives took a long time:" << elapsed/1000.0 << "seconds";

        // Sleep based on current mode
        int sleepSeconds = (currentMode == ScanMode::Slow) ? 5 : 1;

        // Use interruptible sleep - check mode and refresh flag periodically
        for (int i = 0; i < sleepSeconds && !_terminate; ++i) {
            QMutexLocker lock(&_mutex);
            if (_scanMode == ScanMode::Paused || _refreshRequested) {
                break;  // Mode changed or refresh requested, exit sleep early
            }
            lock.unlock();
            QThread::sleep(1);
        }
    }
}
