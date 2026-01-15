/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

// Error dialog with icon, title, message, and single action button.
// Extends WarningDialog with error-specific styling (red icon, "✕" symbol).
// Use for error notifications that need visual emphasis.
//
// Example usage:
//   ErrorDialog {
//       id: errorDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       title: qsTr("Error")
//       message: qsTr("Something went wrong.")
//       onAccepted: { ... }
//   }
WarningDialog {
    id: root

    // Override icon styling for error appearance
    headerIconBackgroundColor: Style.formLabelErrorColor
    headerIconText: "✕"
    headerIconAccessibleName: qsTr("Error icon")
}
