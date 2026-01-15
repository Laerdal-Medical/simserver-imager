/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

// Confirmation dialog with title, message, and two action buttons (cancel/confirm).
// Extends MessageDialog with an additional cancel button using footerButtons.
// Use for actions that require user confirmation before proceeding.
//
// Example usage:
//   ConfirmDialog {
//       id: quitDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       title: qsTr("Are you sure?")
//       message: qsTr("This action cannot be undone.")
//       cancelText: CommonStrings.no
//       confirmText: CommonStrings.yes
//       onRejected: { ... }
//       onAccepted: { ... }
//   }
MessageDialog {
    id: root

    // Override button text to use confirmText
    buttonText: root.confirmText
    buttonAccessibleDescription: root.confirmAccessibleDescription

    // Use destructive styling for confirm button by default
    destructiveButton: root.destructiveConfirm

    // Connect confirmEnabled to buttonEnabled
    buttonEnabled: root.confirmEnabled

    // Confirm dialog specific properties
    property string cancelText: CommonStrings.no
    property string confirmText: CommonStrings.yes
    property string cancelAccessibleDescription: qsTr("Cancel and close this dialog")
    property string confirmAccessibleDescription: qsTr("Confirm this action")

    // Whether to use destructive (red) styling for the confirm button
    property bool destructiveConfirm: true

    // Whether the confirm button is enabled (for form validation)
    property bool confirmEnabled: true

    // Note: rejected() signal is inherited from Dialog base class

    // Override escape handling to emit rejected
    function escapePressed() {
        root.close()
        root.rejected()
    }

    // Add cancel button before the confirm button
    footerButtons: [
        ImButton {
            id: cancelButton
            text: root.cancelText
            accessibleDescription: root.cancelAccessibleDescription
            onClicked: {
                root.close()
                root.rejected()
            }
        }
    ]

    // Override focus groups for the two-button layout
    Component.onCompleted: {
        registerFocusGroup("content", function(){
            if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                return [titleTextItem, messageTextItem]
            }
            return []
        }, 0)
        registerFocusGroup("buttons", function(){
            return [cancelButton, root.actionButtonItem]
        }, 1)
    }
}
