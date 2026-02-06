/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma Singleton

import QtQuick

Item {
    id: root

    // === LAERDAL BRAND COLORS ===
    // From Laerdal Life Design System: https://life.laerdal.com/5d20fd236/p/42a98c-color
    readonly property color mainBackgroundColor: "#ffffff"
    readonly property color backgroundColor: mainBackgroundColor  // Alias for convenience
    readonly property color laerdalBlue: "#2e7fa1"           // Primary brand accent
    readonly property color laerdalDarkBlue: "#1a5a73"       // Darker variant for focus states
    readonly property color laerdalLightBlue: "#5fa8c4"      // Lighter variant
    readonly property color laerdalRed: "#f24235"            // Active/alert accent
    readonly property color transparent: "transparent"

    // Text colors (Laerdal Life Design System)
    readonly property color textColorPrimary: "#212121"      // Primary dark text
    readonly property color textColorSecondary: "#2a2a2a"    // Secondary/body text
    readonly property color textColorOnDark: "#ffffff"       // Text on dark backgrounds

    // Semantic colors for status/feedback (Laerdal Life Design System)
    readonly property color successColor: "#63913f"          // Laerdal success green
    readonly property color successBackgroundColor: "#EBF6ED" // Do/success background
    readonly property color errorColor: "#d32f2f"            // Red for error states
    readonly property color errorBackgroundColor: "#FFEEEB"  // Don't/error background
    readonly property color warningBackgroundColor: "#FFF6F0" // Light peachy callout
    readonly property color warningTextColor: "#b18133"      // Dark yellow/brown text for warnings
    readonly property color infoBackgroundColor: "#C8E2F1"   // Light blue info callout
    readonly property color accentColor: laerdalBlue         // Accent color for highlights
    readonly property color cardBackground: "#fafafa"        // Laerdal light background

    readonly property color buttonBackgroundColor: mainBackgroundColor
    readonly property color buttonForegroundColor: laerdalBlue
    readonly property color buttonDisabledBackgroundColor: "#805fa8c4"
    readonly property color buttonDisabledForegroundColor: "#5fa8c4"
    
    readonly property color buttonFocusedBackgroundColor: "#a05fa8c4"
    readonly property color buttonHoveredBackgroundColor: '#7fc5e0'

    readonly property color button2BackgroundColor: laerdalBlue
    readonly property color button2ForegroundColor: mainBackgroundColor
    readonly property color button2FocusedForegroundColor: laerdalBlueLight
    readonly property color button2DisabledBackgroundColor: "#702e7fa1"
    readonly property color button2DisabledForegroundColor: "#5fa8c4"
    // Focused: noticeably darker for strong state indication (keyboard focus)
    readonly property color button2FocusedBackgroundColor: laerdalDarkBlue
    // Hovered: noticeably lighter to differentiate from base (≥4.5:1 contrast vs base)
    readonly property color button2HoveredBackgroundColor: '#5fb8db'
    // Hovered foreground should be Laerdal Blue for ≥4.5:1 contrast on the light hover bg
    readonly property color button2HoveredForegroundColor: laerdalBlue

    readonly property color titleBackgroundColor: '#f1f5f7'
    readonly property color titleSeparatorColor: "#301a5a73"
    readonly property color popupBorderColor: '#bed5e8f6'
    readonly property color popupDisabledBorderColor: '#405fa7c4'

    readonly property color listViewRowBackgroundColor: "#ffffff"
    readonly property color listViewHoverRowBackgroundColor: "#40BACCE7"
    // Selection highlight color for OS/device lists
    readonly property color listViewHighlightColor: "#80BACCE7"

    // Utility translucent colors
    readonly property color translucentWhite10: Qt.rgba(255, 255, 255, 0.1)
    readonly property color translucentWhite30: Qt.rgba(255, 255, 255, 0.3)

    // descriptions in list views (Laerdal primary text color)
    readonly property color textDescriptionColor: "#2a2a2a"
    // Sidebar colors
    readonly property color sidebarActiveBackgroundColor: laerdalBlue
    readonly property color sidebarTextOnActiveColor: "#FFFFFF"
    readonly property color sidebarTextOnInactiveColor: laerdalBlue
    readonly property color sidebarTextDisabledColor: "#202e7fa1"
    // Sidebar controls
    readonly property color sidebarControlBorderColor: "#502e7fa1"
    readonly property color sidebarBackgroundColour: mainBackgroundColor
    readonly property color sidebarBorderColour: laerdalBlue

    // OS metadata
    readonly property color textMetadataColor: "#646464"

    // for the "device / OS / storage" titles
    readonly property color subtitleColor: "#ffffff"

    readonly property color progressBarTextColor: '#70c6e8'
    readonly property color progressBarVerifyForegroundColor: successColor  // Laerdal success green
    readonly property color progressBarBackgroundColor: laerdalBlue
    // New: distinct colors for writing vs verification phases
    readonly property color progressBarWritingForegroundColor: laerdalBlue
    readonly property color progressBarTrackColor: '#eefafe'

    readonly property color lanbarBackgroundColor: "#ffffe3"

    /// the check-boxes/radio-buttons have labels that might be disabled
    readonly property color formLabelColor: "black"
    readonly property color formLabelErrorColor: "red"
    readonly property color formLabelDisabledColor: "#202e7fa1"
    // Active color for radio buttons, checkboxes, and switches
    readonly property color formControlActiveColor: laerdalBlue

    readonly property color embeddedModeInfoTextColor: "#ffffff"

    // Focus/outline
    readonly property color focusOutlineColor: laerdalBlue
    readonly property int focusOutlineWidth: 2
    readonly property int focusOutlineRadius: 4
    readonly property int focusOutlineMargin: -4

    // === FONTS ===
    readonly property alias fontFamily: roboto.name
    readonly property alias fontFamilyLight: robotoLight.name
    readonly property alias fontFamilyBold: robotoBold.name

    // Font sizes
    // Base scale (single source of truth)
    readonly property int fontSizeXs: 12
    readonly property int fontSizeSm: 14
    readonly property int fontSizeMd: 16
    readonly property int fontSizeXl: 24

    // Role tokens mapped to base scale
    readonly property int fontSizeTitle: fontSizeXl
    readonly property int fontSizeHeading: fontSizeMd
    readonly property int fontSizeLargeHeading: fontSizeMd
    readonly property int fontSizeFormLabel: fontSizeSm
    readonly property int fontSizeSubtitle: fontSizeSm
    readonly property int fontSizeDescription: fontSizeXs
    readonly property int fontSizeProgressBar: fontSizeMd
    readonly property int fontSizeInput: fontSizeXs
    readonly property int fontSizeCaption: fontSizeXs
    readonly property int fontSizeSmall: fontSizeXs
    readonly property int fontSizeSidebarItem: fontSizeSm

    // === SPACING ===
    readonly property int spacingXXSmall: 2
    readonly property int spacingXSmall: 5
    readonly property int spacingTiny: 8
    readonly property int spacingSmall: 10
    readonly property int spacingSmallPlus: 12
    readonly property int spacingMedium: 15
    readonly property int spacingLarge: 20
    readonly property int spacingExtraLarge: 30

    // === SIZES ===
    readonly property int buttonHeightStandard: 40
    readonly property int buttonWidthMinimum: 120
    readonly property int buttonWidthSkip: 150

    // Border radii
    readonly property int radiusSmall: 4
    readonly property int radiusMedium: 8

    readonly property int sectionMaxWidth: 500
    readonly property int sectionMargins: 24
    readonly property int sectionPadding: 16
    readonly property int sectionBorderWidth: 1
    readonly property int sectionBorderRadius: 8
    readonly property int listItemBorderRadius: 5
    readonly property int listItemPadding: 15
    readonly property int cardPadding: 20
    readonly property int scrollBarWidth: 10
    readonly property int sidebarWidth: 200
    readonly property int sidebarItemBorderRadius: 4
    // Embedded-mode overrides (0 radius to avoid software renderer artifacts)
    readonly property int sectionBorderRadiusEmbedded: 0
    readonly property int listItemBorderRadiusEmbedded: 0
    readonly property int sidebarItemBorderRadiusEmbedded: 0
    readonly property int buttonBorderRadiusEmbedded: 0
    // Sidebar item heights
    readonly property int sidebarItemHeight: buttonHeightStandard
    readonly property int sidebarSubItemHeight: sidebarItemHeight - 12

    // === LAYOUT ===
    readonly property int formColumnSpacing: 20
    readonly property int formRowSpacing: 15
    readonly property int stepContentMargins: 24
    readonly property int stepContentSpacing: 16

    // Font loaders
    FontLoader { id: roboto;      source: "fonts/Roboto-Regular.ttf" }
    FontLoader { id: robotoLight; source: "fonts/Roboto-Light.ttf" }
    FontLoader { id: robotoBold;  source: "fonts/Roboto-Bold.ttf" }
}
