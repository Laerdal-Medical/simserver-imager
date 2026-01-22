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
}
