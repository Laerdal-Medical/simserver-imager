/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Layouts
import RpiImager

/**
 * A banner component that displays a message with optional loading indicator.
 * Supports different banner types (Info, Warning, Error, Success) with appropriate styling.
 * Can optionally include action components (buttons, etc.) by adding them as children.
 */
Rectangle {
    id: root

    // Allow child items to be added to the action area
    default property alias actions: actionContainer.data

    // Banner type enum
    enum Type {
        Info,       // Default blue/neutral style
        Warning,    // Yellow/orange warning style
        Error,      // Red error style
        Success     // Green success style
    }

    // The banner type - determines colors and icon
    property int bannerType: ImBanner.Type.Info

    // The message to display
    property string text: ""

    // Whether to show loading spinner (takes precedence over type icon)
    property bool loading: false

    // Optional: override background color (if not set, uses type-based color from Laerdal Design System)
    property color bannerColor: {
        switch (root.bannerType) {
            case ImBanner.Type.Warning: return Style.warningBackgroundColor
            case ImBanner.Type.Error:   return Style.errorBackgroundColor
            case ImBanner.Type.Success: return Style.successBackgroundColor
            default:                    return Style.infoBackgroundColor
        }
    }

    // Optional: override text color (if not set, uses type-based color)
    property color textColor: {
        switch (root.bannerType) {
            case ImBanner.Type.Warning: return Style.warningTextColor
            case ImBanner.Type.Error:   return Style.errorColor
            case ImBanner.Type.Success: return Style.successColor
            default:                    return Style.textColorPrimary
        }
    }

    // Icon text based on type
    readonly property string typeIcon: {
        switch (root.bannerType) {
            case ImBanner.Type.Warning: return "\u26A0"  // Warning sign
            case ImBanner.Type.Error:   return "\u2716"  // X mark
            case ImBanner.Type.Success: return "\u2714"  // Check mark
            default:                    return ""
        }
    }

    Layout.fillWidth: true
    Layout.preferredHeight: visible ? bannerContent.implicitHeight + Style.spacingSmall * 2 : 0
    color: root.bannerColor
    radius: Style.sectionBorderRadius

    Behavior on Layout.preferredHeight {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutQuad
        }
    }

    RowLayout {
        id: bannerContent
        anchors.fill: parent
        anchors.leftMargin: Style.spacingMedium
        anchors.rightMargin: Style.spacingMedium
        anchors.topMargin: Style.spacingSmall
        anchors.bottomMargin: Style.spacingSmall
        spacing: Style.spacingSmall

        // Loading spinner (shown when loading is true)
        ImBusyIndicator {
            visible: root.loading
            running: root.loading
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
        }

        // Type icon (shown when not loading and type has an icon)
        Text {
            visible: !root.loading && root.typeIcon.length > 0
            text: root.typeIcon
            font.pixelSize: Style.fontSizeFormLabel
            color: root.textColor
        }

        // Message text
        Text {
            text: root.text
            font.pixelSize: Style.fontSizeDescription
            font.family: Style.fontFamily
            color: root.textColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.StaticText
            Accessible.name: root.text
        }

        // Container for optional action items (buttons, etc.)
        Row {
            id: actionContainer
            spacing: Style.spacingSmall
            visible: children.length > 0
        }
    }
}
