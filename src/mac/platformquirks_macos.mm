/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

#include "../platformquirks.h"
#include <cstdlib>
#include <cstdio>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/time.h>
#include <QProcess>
#include <QElapsedTimer>
#include <QThread>
#import <AppKit/AppKit.h>
#import <SystemConfiguration/SystemConfiguration.h>

namespace {
    // Network monitoring state
    SCNetworkReachabilityRef g_reachabilityRef = nullptr;
    PlatformQuirks::NetworkStatusCallback g_networkCallback = nullptr;
    
    void reachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
        (void)target;
        (void)info;
        
        if (!g_networkCallback) return;
        
        bool isReachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
        bool needsConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
        bool isAvailable = isReachable && !needsConnection;
        
        fprintf(stderr, "Network status changed: reachable=%d needsConnection=%d\n", isReachable, needsConnection);
        g_networkCallback(isAvailable);
    }
}

namespace PlatformQuirks {

void applyQuirks() {
    // Currently no platform-specific quirks needed for macOS
    // macOS has a sensible permissions model that operates as expected
    
    // Example of how to set environment variables without Qt:
    // setenv("VARIABLE_NAME", "value", 1);
}

void beep() {
    // Use macOS NSBeep for system beep sound
    NSBeep();
}

bool hasNetworkConnectivity() {
    // Use SystemConfiguration framework to check network reachability
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "www.raspberrypi.com");
    if (!reachability) {
        return false;
    }
    
    SCNetworkReachabilityFlags flags;
    bool success = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    
    if (!success) {
        return false;
    }
    
    // Check if network is reachable
    bool isReachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    // Check if connection is required (e.g., captive portal)
    bool needsConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
    
    return isReachable && !needsConnection;
}

bool isNetworkReady() {
    // On macOS, no special time sync check needed - system time is reliable
    return hasNetworkConnectivity();
}

void startNetworkMonitoring(NetworkStatusCallback callback) {
    // Stop any existing monitoring
    stopNetworkMonitoring();
    
    g_networkCallback = callback;
    
    // Create reachability reference for a known host
    g_reachabilityRef = SCNetworkReachabilityCreateWithName(NULL, "www.raspberrypi.com");
    if (!g_reachabilityRef) {
        fprintf(stderr, "Failed to create network reachability reference\n");
        return;
    }
    
    // Set up callback context
    SCNetworkReachabilityContext context = {0, nullptr, nullptr, nullptr, nullptr};
    
    if (!SCNetworkReachabilitySetCallback(g_reachabilityRef, reachabilityCallback, &context)) {
        fprintf(stderr, "Failed to set network reachability callback\n");
        CFRelease(g_reachabilityRef);
        g_reachabilityRef = nullptr;
        return;
    }
    
    // Schedule on main run loop
    if (!SCNetworkReachabilityScheduleWithRunLoop(g_reachabilityRef, CFRunLoopGetMain(), kCFRunLoopDefaultMode)) {
        fprintf(stderr, "Failed to schedule network reachability on run loop\n");
        CFRelease(g_reachabilityRef);
        g_reachabilityRef = nullptr;
        return;
    }
    
    fprintf(stderr, "Network monitoring started\n");
}

void stopNetworkMonitoring() {
    if (g_reachabilityRef) {
        SCNetworkReachabilityUnscheduleFromRunLoop(g_reachabilityRef, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        CFRelease(g_reachabilityRef);
        g_reachabilityRef = nullptr;
        fprintf(stderr, "Network monitoring stopped\n");
    }
    g_networkCallback = nullptr;
}

void bringWindowToForeground(void* windowHandle) {
    // No-op on macOS - not implemented
    // macOS handles window activation differently and has restrictions on
    // applications bringing themselves to the foreground
    (void)windowHandle;
}

bool hasElevatedPrivileges() {
    // macOS has a sensible permissions model that operates as expected
    // No special privilege check needed - return true
    return true;
}

void attachConsole() {
    // No-op on macOS - console is already available
}

bool isElevatableBundle() {
    // macOS .app bundles don't need this mechanism - Authorization Services handles elevation
    return false;
}

const char* getBundlePath() {
    // Not applicable on macOS
    return nullptr;
}

bool hasElevationPolicyInstalled() {
    // Not applicable on macOS
    return false;
}

bool installElevationPolicy() {
    // Not applicable on macOS
    return false;
}

bool tryElevate(int argc, char** argv) {
    // macOS uses Authorization Services, not polkit-style elevation
    (void)argc;
    (void)argv;
    return false;
}

bool launchDetached(const QString& program, const QStringList& arguments) {
    // On macOS, QProcess::startDetached works correctly for launching
    // detached processes that outlive the parent
    return QProcess::startDetached(program, arguments);
}

bool runElevatedPolicyInstaller() {
    return false;
}

void execElevated(const QStringList& extraArgs) {
    Q_UNUSED(extraArgs);
}

bool isScrollInverted(bool qtInvertedFlag) {
    // On macOS, Qt correctly reports the inverted flag in WheelEvent
    // so we just pass through the Qt value.
    return qtInvertedFlag;
}

QString getWriteDevicePath(const QString& devicePath) {
    // On macOS, use raw disk device (/dev/rdisk) for direct I/O.
    // This bypasses the macOS buffer cache and provides significantly
    // faster write performance for large sequential writes.
    QString result = devicePath;
    result.replace("/dev/disk", "/dev/rdisk");
    return result;
}

QString getEjectDevicePath(const QString& devicePath) {
    // Convert back to block device path for eject operations.
    // While DADiskCreateFromBSDName technically accepts both forms,
    // using /dev/disk is the canonical form for disk operations.
    QString result = devicePath;
    result.replace("/dev/rdisk", "/dev/disk");
    return result;
}

bool waitForDeviceReady(const QString& devicePath, int timeoutMs) {
    // Poll the device file descriptor until it's accessible for writing.
    // On macOS, we use the block device path (/dev/disk) for this check.
    // This is more reliable than a fixed sleep because:
    // 1. Returns immediately when device is ready (faster)
    // 2. Waits longer if device needs more time (more robust)
    // 3. Provides clear success/failure feedback

    // Use block device path for readiness check
    QString blockDevicePath = getEjectDevicePath(devicePath);
    QByteArray deviceBytes = blockDevicePath.toUtf8();
    const char* device = deviceBytes.constData();

    QElapsedTimer timer;
    timer.start();

    const int pollIntervalMs = 50;  // Check every 50ms
    int lastErrno = 0;

    while (timer.elapsed() < timeoutMs) {
        // Try to open device with exclusive access
        // O_EXLOCK ensures no other process has the device open
        int fd = ::open(device, O_RDWR | O_EXLOCK | O_NONBLOCK);
        if (fd >= 0) {
            ::close(fd);
            fprintf(stderr, "Device %s ready after %lld ms\n",
                    device, timer.elapsed());
            return true;
        }

        lastErrno = errno;

        // EBUSY means device is in use - keep waiting
        // EAGAIN/EWOULDBLOCK can happen with O_NONBLOCK - keep waiting
        if (lastErrno != EBUSY && lastErrno != EAGAIN && lastErrno != EWOULDBLOCK) {
            // For other errors, try without O_EXLOCK as fallback
            // Some devices don't support exclusive locking
            fd = ::open(device, O_RDWR | O_NONBLOCK);
            if (fd >= 0) {
                ::close(fd);
                fprintf(stderr, "Device %s ready (non-exclusive) after %lld ms\n",
                        device, timer.elapsed());
                return true;
            }
        }

        QThread::msleep(pollIntervalMs);
    }

    fprintf(stderr, "Device %s not ready after %d ms, last error: %s\n",
            device, timeoutMs, strerror(lastErrno));
    return false;
}

} // namespace PlatformQuirks