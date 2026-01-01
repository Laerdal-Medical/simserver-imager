/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import RpiImager

/**
 * A convenience wrapper for ImBanner that shows a loading spinner.
 * Visibility is controlled by the 'active' property.
 */
ImBanner {
    id: root

    // Whether the banner is active (controls visibility and spinner)
    property bool active: false

    visible: root.active
    loading: true  // Always show spinner when visible
}
