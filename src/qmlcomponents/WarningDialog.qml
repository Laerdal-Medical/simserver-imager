/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

// Warning dialog with icon, title, message, and single action button.
// Extends MessageDialog with a warning icon to the left of the title.
// Use for important notifications that need visual emphasis (e.g., device removed).
//
// Example usage:
//   WarningDialog {
//       id: storageRemovedDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       title: qsTr("Storage device removed")
//       message: qsTr("The device is no longer available.")
//       buttonText: qsTr("OK")
//       onAccepted: { ... }
//   }
MessageDialog {
    id: root

    // Override default button text
    buttonText: qsTr("OK")

    // Enable header icon with warning styling
    headerIconVisible: true
    headerIconBackgroundColor: Style.warningTextColor
    headerIconText: "!"
    headerIconAccessibleName: qsTr("Warning icon")

}
