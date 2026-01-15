/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

// Message dialog with title, message, optional secondary action button, and primary button.
// Extends MessageDialog to add an optional action button on the left side.
//
// Example usage:
//   ActionMessageDialog {
//       id: permissionDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       dialogTitle: qsTr("Permission Warning")
//       message: warningMessage
//       secondaryButtonText: qsTr("Install Authorization")
//       secondaryButtonVisible: canInstallAuth
//       onSecondaryAction: { ... }
//       onAccepted: { ... }
//   }
MessageDialog {
    id: root

    // Override default button text
    buttonText: qsTr("OK")

    // Secondary action button properties
    property string secondaryButtonText: ""
    property string secondaryButtonAccessibleDescription: ""
    property bool secondaryButtonVisible: false

    // Additional signal for secondary action
    signal secondaryAction()

    // Helper function to open with a message
    function showWarning(msg) {
        root.message = msg
        root.open()
    }

    // Override focus groups to include secondary button
    Component.onCompleted: {
        registerFocusGroup("content", function(){
            if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                return [titleTextItem, messageTextItem]
            }
            return []
        }, 0)
        registerFocusGroup("buttons", function(){
            var buttons = []
            if (secondaryButton.visible) {
                buttons.push(secondaryButton)
            }
            buttons.push(actionButton)
            return buttons
        }, 1)
    }

    // Override footer with optional secondary action button
    footer: RowLayout {
        width: parent ? parent.width : 0
        height: Style.buttonHeightStandard + (Style.cardPadding * 2)
        spacing: Style.spacingMedium

        Item { Layout.preferredWidth: Style.cardPadding }

        // Optional secondary action button (left side)
        ImButton {
            id: secondaryButton
            text: root.secondaryButtonText
            accessibleDescription: root.secondaryButtonAccessibleDescription
            Layout.preferredHeight: Style.buttonHeightStandard
            activeFocusOnTab: true
            visible: root.secondaryButtonVisible && root.secondaryButtonText.length > 0
            onClicked: {
                root.secondaryAction()
            }
        }

        Item { Layout.fillWidth: true }

        // Primary action button (right side)
        ImButton {
            id: actionButton
            text: root.buttonText
            accessibleDescription: root.buttonAccessibleDescription
            Layout.preferredHeight: Style.buttonHeightStandard
            activeFocusOnTab: true
            onClicked: {
                root.close()
                root.accepted()
            }
        }

        Item { Layout.preferredWidth: Style.cardPadding }
    }
}
