/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma Singleton

import QtQuick

QtObject {
    /**
     * Calculate download/network throughput in megabits per second (Mbps)
     *
     * This helper manages the calculation of network speed with exponential moving
     * average smoothing and proper time-based sampling.
     *
     * @param bytesNow - Current bytes downloaded/transferred
     * @param lastBytes - Previous bytes value (pass as reference via object property)
     * @param lastTime - Previous timestamp in milliseconds (pass as reference via object property)
     * @param currentThroughput - Current throughput value for EMA smoothing
     * @param sampleIntervalMs - Minimum interval between calculations (default: 500ms)
     * @param smoothingAlpha - EMA smoothing factor (default: 0.3, range 0-1)
     * @returns Object with { throughputMbps, newLastBytes, newLastTime } or null if no update
     */
    function calculateThroughputMbps(bytesNow, lastBytes, lastTime, currentThroughput, sampleIntervalMs, smoothingAlpha) {
        var interval = sampleIntervalMs !== undefined ? sampleIntervalMs : 500
        var alpha = smoothingAlpha !== undefined ? smoothingAlpha : 0.3

        var currentTime = Date.now()

        // First call - initialize tracking
        if (lastTime === 0 || lastTime === undefined) {
            return {
                throughputMbps: 0,
                newLastBytes: bytesNow,
                newLastTime: currentTime
            }
        }

        var timeElapsed = (currentTime - lastTime) / 1000  // Convert to seconds

        // Not enough time elapsed, don't update
        if (timeElapsed < interval / 1000) {
            return null
        }

        var bytesDelta = bytesNow - lastBytes
        if (bytesDelta <= 0 || timeElapsed <= 0) {
            // No progress or invalid data
            return {
                throughputMbps: currentThroughput || 0,
                newLastBytes: bytesNow,
                newLastTime: currentTime
            }
        }

        var bytesPerSecond = bytesDelta / timeElapsed
        // Convert to megabits per second: bytes/s * 8 bits/byte / 1,000,000 bits/Mbit
        var instantThroughputMbps = (bytesPerSecond * 8) / 1000000

        // Apply exponential moving average for smoothing
        var newThroughput
        if (currentThroughput === 0 || currentThroughput === undefined) {
            newThroughput = instantThroughputMbps
        } else {
            newThroughput = alpha * instantThroughputMbps + (1 - alpha) * currentThroughput
        }

        return {
            throughputMbps: newThroughput,
            newLastBytes: bytesNow,
            newLastTime: currentTime
        }
    }

    /**
     * Calculate disk I/O throughput in kilobytes per second (KB/s)
     *
     * This helper manages the calculation of disk write/read speed without smoothing,
     * suitable for verify operations where raw speed is preferred.
     *
     * @param bytesNow - Current bytes written/read
     * @param lastBytes - Previous bytes value (pass as reference via object property)
     * @param lastTime - Previous timestamp in milliseconds (pass as reference via object property)
     * @param sampleIntervalMs - Minimum interval between calculations (default: 500ms)
     * @returns Object with { throughputKBps, newLastBytes, newLastTime } or null if no update
     */
    function calculateThroughputKBps(bytesNow, lastBytes, lastTime, sampleIntervalMs) {
        var interval = sampleIntervalMs !== undefined ? sampleIntervalMs : 500

        var currentTime = Date.now()

        // First call - initialize tracking
        if (lastTime === 0 || lastTime === undefined) {
            return {
                throughputKBps: 0,
                newLastBytes: bytesNow,
                newLastTime: currentTime
            }
        }

        var timeDelta = currentTime - lastTime

        // Not enough time elapsed, don't update
        if (timeDelta < interval) {
            return null
        }

        var bytesDelta = bytesNow - lastBytes
        if (bytesDelta <= 0 || timeDelta <= 0) {
            // No progress or invalid data
            return {
                throughputKBps: 0,
                newLastBytes: bytesNow,
                newLastTime: currentTime
            }
        }

        // Calculate KB/s: (bytes / 1024) / (ms / 1000) = bytes * 1000 / 1024 / ms
        var throughputKBps = Math.round((bytesDelta * 1000) / (1024 * timeDelta))

        return {
            throughputKBps: throughputKBps,
            newLastBytes: bytesNow,
            newLastTime: currentTime
        }
    }

    /**
     * Format bytes to human-readable string
     *
     * Converts byte values to appropriate units (B, KB, MB, GB) with proper precision.
     *
     * @param bytes - Number of bytes to format
     * @returns Formatted string like "1.5 GB", "234.7 MB", "45.2 KB", or "512 B"
     */
    function formatBytes(bytes) {
        if (bytes < 1024) {
            return qsTr("%1 B").arg(Math.round(bytes))
        }
        if (bytes < 1024 * 1024) {
            return qsTr("%1 KB").arg((bytes / 1024).toFixed(1))
        }
        if (bytes < 1024 * 1024 * 1024) {
            return qsTr("%1 MB").arg((bytes / (1024 * 1024)).toFixed(1))
        }
        return qsTr("%1 GB").arg((bytes / (1024 * 1024 * 1024)).toFixed(2))
    }

    /**
     * Calculate average transfer speed in MB/s
     *
     * Calculates the average speed for data transfer operations (write/verify).
     *
     * @param bytes - Total bytes transferred
     * @param seconds - Total time in seconds
     * @returns Formatted string like "45.3 MB/s" or empty string if invalid
     */
    function calculateAverageSpeed(bytes, seconds) {
        if (seconds <= 0) return ""
        var mbps = bytes / (1024 * 1024) / seconds
        return qsTr("%1 MB/s").arg(mbps.toFixed(1))
    }

    /**
     * Format duration in seconds to human-readable string
     *
     * Converts duration in seconds to appropriate time units (seconds, minutes, hours).
     *
     * @param seconds - Duration in seconds
     * @returns Formatted string like "45 seconds", "3 min 12 sec", "2 hr 15 min", or empty if invalid
     */
    function formatDuration(seconds) {
        if (seconds < 0 || !isFinite(seconds)) {
            return ""
        }
        var secs = Math.round(seconds)
        if (secs < 60) {
            return qsTr("%n second(s)", "", secs)
        }
        var minutes = Math.floor(secs / 60)
        var remainingSecs = secs % 60
        if (minutes < 60) {
            if (remainingSecs > 0) {
                return qsTr("%1 min %2 sec").arg(minutes).arg(remainingSecs)
            }
            return qsTr("%n minute(s)", "", minutes)
        }
        var hours = Math.floor(minutes / 60)
        var remainingMins = minutes % 60
        if (remainingMins > 0) {
            return qsTr("%1 hr %2 min").arg(hours).arg(remainingMins)
        }
        return qsTr("%n hour(s)", "", hours)
    }

    /**
     * Format time remaining in seconds to human-readable string
     *
     * Converts time remaining in seconds to appropriate time units with "remaining" suffix.
     *
     * @param seconds - Time remaining in seconds
     * @returns Formatted string like "45 seconds remaining", "3 min 12 sec remaining", "2 hr 15 min remaining", or empty if invalid
     */
    function formatTimeRemaining(seconds) {
        if (seconds < 0 || !isFinite(seconds)) {
            return ""
        }
        if (seconds < 60) {
            return qsTr("%n second(s) remaining", "", seconds)
        }
        var minutes = Math.floor(seconds / 60)
        var remainingSeconds = seconds % 60
        if (minutes < 60) {
            if (remainingSeconds > 0) {
                return qsTr("%1 min %2 sec remaining").arg(minutes).arg(remainingSeconds)
            }
            return qsTr("%n minute(s) remaining", "", minutes)
        }
        var hours = Math.floor(minutes / 60)
        var remainingMinutes = minutes % 60
        if (remainingMinutes > 0) {
            return qsTr("%1 hr %2 min remaining").arg(hours).arg(remainingMinutes)
        }
        return qsTr("%n hour(s) remaining", "", hours)
    }

    /**
     * Calculate estimated time remaining for write/verify operations
     *
     * Calculates time remaining based on disk I/O throughput in KB/s.
     *
     * @param bytesNow - Current bytes transferred
     * @param bytesTotal - Total bytes to transfer
     * @param throughputKBps - Current throughput in kilobytes per second
     * @returns Estimated seconds remaining, or -1 if invalid, or 0 if complete
     */
    function calculateTimeRemainingKBps(bytesNow, bytesTotal, throughputKBps) {
        if (throughputKBps <= 0 || bytesTotal <= 0) {
            return -1
        }
        var remainingBytes = bytesTotal - bytesNow
        if (remainingBytes <= 0) {
            return 0
        }
        // throughput is in KB/s, convert to bytes/s
        var bytesPerSecond = throughputKBps * 1024
        return Math.ceil(remainingBytes / bytesPerSecond)
    }

    /**
     * Calculate estimated time remaining for download operations
     *
     * Calculates time remaining based on network throughput in Mbps.
     *
     * @param bytesNow - Current bytes downloaded
     * @param bytesTotal - Total bytes to download
     * @param throughputMbps - Current throughput in megabits per second
     * @returns Estimated seconds remaining, or -1 if invalid, or 0 if complete
     */
    function calculateTimeRemainingMbps(bytesNow, bytesTotal, throughputMbps) {
        if (throughputMbps <= 0 || bytesTotal <= 0) {
            return -1
        }
        var remainingBytes = bytesTotal - bytesNow
        if (remainingBytes <= 0) {
            return 0
        }
        // throughput is in Mbps (megabits/s), convert to bytes/s: Mbps * 1,000,000 / 8
        var bytesPerSecond = (throughputMbps * 1000000) / 8
        return Math.ceil(remainingBytes / bytesPerSecond)
    }
}
