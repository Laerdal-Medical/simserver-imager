/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

// Confirmation dialog with title, message, and two action buttons (cancel/confirm).
// Extends MessageDialog with an additional cancel button.
// Use for actions that require user confirmation before proceeding.
//
// Example usage:
//   ConfirmDialog {
//       id: quitDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       dialogTitle: qsTr("Are you sure?")
//       message: qsTr("This action cannot be undone.")
//       cancelText: CommonStrings.no
//       confirmText: CommonStrings.yes
//       onRejected: { ... }
//       onAccepted: { ... }
//   }
MessageDialog {
    id: root

    // Override button text to use confirmText
    buttonText: confirmText

    // Confirm dialog specific properties
    property string cancelText: CommonStrings.no
    property string confirmText: CommonStrings.yes
    property string cancelAccessibleDescription: qsTr("Cancel and close this dialog")
    property string confirmAccessibleDescription: qsTr("Confirm this action")

    // Whether to use destructive (red) styling for the confirm button
    property bool destructiveConfirm: true

    // Note: rejected() signal is inherited from Dialog base class

    // Override escape handling to emit rejected
    function escapePressed() {
        root.close()
        root.rejected()
    }

    // Override focus groups for the two-button layout
    Component.onCompleted: {
        registerFocusGroup("content", function(){
            if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                return [titleTextItem, messageTextItem]
            }
            return []
        }, 0)
        registerFocusGroup("buttons", function(){
            var confirmBtn = root.destructiveConfirm ? destructiveConfirmButton : normalConfirmButton
            return [cancelButton, confirmBtn]
        }, 1)
    }

    // Override footer with cancel and confirm buttons
    footer: RowLayout {
        width: parent ? parent.width : 0
        height: Style.buttonHeightStandard + (Style.cardPadding * 2)
        spacing: Style.spacingMedium

        Item { Layout.preferredWidth: Style.cardPadding }
        Item { Layout.fillWidth: true }

        ImButton {
            id: cancelButton
            text: root.cancelText
            accessibleDescription: root.cancelAccessibleDescription
            Layout.preferredHeight: Style.buttonHeightStandard
            activeFocusOnTab: true
            onClicked: {
                root.close()
                root.rejected()
            }
        }

        // Destructive (red) confirm button
        ImButtonRed {
            id: destructiveConfirmButton
            text: root.confirmText
            accessibleDescription: root.confirmAccessibleDescription
            Layout.preferredHeight: Style.buttonHeightStandard
            activeFocusOnTab: true
            visible: root.destructiveConfirm
            onClicked: {
                root.close()
                root.accepted()
            }
        }

        // Normal confirm button
        ImButton {
            id: normalConfirmButton
            text: root.confirmText
            accessibleDescription: root.confirmAccessibleDescription
            Layout.preferredHeight: Style.buttonHeightStandard
            activeFocusOnTab: true
            visible: !root.destructiveConfirm
            onClicked: {
                root.close()
                root.accepted()
            }
        }

        Item { Layout.preferredWidth: Style.cardPadding }
    }
}
