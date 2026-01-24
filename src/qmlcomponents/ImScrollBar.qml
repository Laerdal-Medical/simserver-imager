/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import RpiImager

// Reusable scrollbar component with Laerdal brand styling and rounded corners
ScrollBar {
    id: root

    // Color customization
    property color handleColor: Style.laerdalBlue
    property color trackColor: Style.progressBarTrackColor
    property color handleHoverColor: Style.laerdalLightBlue
    property color handlePressedColor: Style.laerdalDarkBlue
    property Flickable flickable: null

    implicitWidth: Style.scrollBarWidth
    implicitHeight: Style.scrollBarWidth

    // Customize the scrollbar background (track)
    background: Rectangle {
        color: root.trackColor
        radius: root.horizontal ? height / 2 : width / 2
        opacity: 0.3
    }

    // Customize the scrollbar handle
    contentItem: Rectangle {
        implicitWidth: root.horizontal ? 100 : Style.scrollBarWidth
        implicitHeight: root.horizontal ? Style.scrollBarWidth : 100
        radius: root.horizontal ? height / 2 : width / 2
        color: root.pressed ? root.handlePressedColor
             : root.hovered ? root.handleHoverColor
             : root.handleColor
        opacity: root.active ? 1.0 : 0.6

        // Smooth opacity transitions
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

        // Smooth color transitions
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }
    policy: {
        if (flickable && flickable.contentHeight > flickable.height) {
            return  ScrollBar.AlwaysOn;
        } 
        return ScrollBar.AsNeeded
    }
    
    // Show/hide animation
    Behavior on opacity {
        NumberAnimation { duration: 150 }
    }
}
