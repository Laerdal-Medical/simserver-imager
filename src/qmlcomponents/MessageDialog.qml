/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

// Simple message dialog with title, message, and single action button.
// Use for informational messages, errors, or notifications that require acknowledgment.
//
// This is the base for other dialog types (ConfirmDialog, WarningDialog, ActionMessageDialog).
// Child dialogs can add extra buttons using the footerButtons property without overriding footer.
//
// Supports flexible content:
// - Set 'message' property for simple text content
// - Add child components for custom content (displayed below message)
// - Use both together for message + additional content
//
// Example usage (simple message):
//   MessageDialog {
//       id: errorDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       title: qsTr("Error")
//       message: "Something went wrong"
//       buttonText: CommonStrings.continueText
//       onAccepted: { ... }
//   }
//
// Example usage (with extra buttons):
//   MessageDialog {
//       id: confirmDialog
//       title: qsTr("Confirm")
//       message: "Are you sure?"
//       buttonText: qsTr("OK")
//
//       footerButtons: [
//           ImButton {
//               text: qsTr("Cancel")
//               onClicked: confirmDialog.close()
//           }
//       ]
//   }
//
// Example usage (custom content):
//   MessageDialog {
//       id: customDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       title: qsTr("Custom Dialog")
//       buttonText: qsTr("OK")
//
//       ColumnLayout {
//           Layout.fillWidth: true
//           Text { text: "Custom content here" }
//           ProgressBar { ... }
//       }
//   }
BaseDialog {
    id: root

    // Dialog content properties
    // Note: 'title' is inherited from Dialog base class
    property string message: ""
    property string buttonText: CommonStrings.continueText
    property string buttonAccessibleDescription: qsTr("Close this dialog")

    // Message styling (can be overridden by child dialogs)
    property int messageAlignment: Text.AlignLeft

    // Custom content support - child items go into customContentContainer
    // When custom content is provided, the default message text is hidden
    default property alias customContent: customContentContainer.data
    readonly property bool hasCustomContent: customContentContainer.children.length > 0

    // Expose text elements for focus group registration in child dialogs
    // Note: titleTextItem is inherited from BaseDialog
    property alias messageTextItem: messageText

    // Expose action button for focus group registration (returns the visible one)
    readonly property Item actionButtonItem: root.destructiveButton ? destructiveActionButton : actionButton

    // Footer buttons - child dialogs can add buttons here (displayed before the primary action button)
    // Use this instead of overriding footer for simpler customization
    property list<Item> footerButtons

    // Whether to use destructive (red) styling for the primary action button
    property bool destructiveButton: false

    // Whether the primary action button is enabled (for form validation)
    property bool buttonEnabled: true

    // Whether to show the footer (allows child dialogs to hide entire footer)
    property bool showFooter: true

    // Note: accepted() signal is inherited from Dialog base class

    // Custom escape handling
    function escapePressed() {
        root.close()
        root.accepted()
    }

    // Register focus groups when component is ready
    Component.onCompleted: {
        registerFocusGroup("content", function(){
            if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                return [messageText]
            }
            return []
        }, 0)
        registerFocusGroup("buttons", function(){
            return [actionButton]
        }, 1)
    }

    // Message text (shown when message is set)
    Text {
        id: messageText
        text: root.message
        textFormat: Text.StyledText
        wrapMode: Text.WordWrap
        font.pixelSize: Style.fontSizeDescription
        font.family: Style.fontFamily
        color: Style.textDescriptionColor
        horizontalAlignment: root.messageAlignment
        Layout.fillWidth: true
        visible: text.length > 0
        Accessible.role: Accessible.StaticText
        Accessible.name: text.replace(/<[^>]+>/g, '')  // Strip HTML tags for accessibility
        Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
        focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
        activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
    }

    // Container for custom content (populated via default property alias)
    // Shown below the message when custom content is provided
    ColumnLayout {
        id: customContentContainer
        Layout.fillWidth: true
        spacing: Style.spacingMedium
        visible: root.hasCustomContent
    }

    // Footer with action button (child dialogs can add buttons via footerButtons property)
    footer: RowLayout {
        id: footerLayout
        // Align with content area (same x and width as contentLayout in BaseDialog)
        width: parent ? parent.width : 0
        height: Style.buttonHeightStandard + (Style.spacingMedium * 2)
        visible: root.showFooter

        spacing: Style.spacingMedium

        // Spacer to push buttons to the right
        Item { Layout.fillWidth: true }

        // Extra buttons from child dialogs (added before the primary action button)
        Repeater {
            model: root.footerButtons
            delegate: Item {
                id: buttonDelegate
                required property Item modelData
                Layout.preferredWidth: buttonDelegate.modelData.implicitWidth
                Layout.preferredHeight: Style.buttonHeightStandard
                Component.onCompleted: {
                    buttonDelegate.modelData.parent = buttonDelegate
                    buttonDelegate.modelData.anchors.fill = buttonDelegate
                }
            }
        }

        // Normal primary action button
        ImButton {
            id: actionButton
            text: root.buttonText
            accessibleDescription: root.buttonAccessibleDescription
            Layout.preferredHeight: Style.buttonHeightStandard
            activeFocusOnTab: true
            visible: !root.destructiveButton
            enabled: root.buttonEnabled
            onClicked: {
                root.close()
                root.accepted()
            }
        }

        // Destructive (red) primary action button
        ImButtonRed {
            id: destructiveActionButton
            text: root.buttonText
            accessibleDescription: root.buttonAccessibleDescription
            Layout.preferredHeight: Style.buttonHeightStandard
            activeFocusOnTab: true
            visible: root.destructiveButton
            enabled: root.buttonEnabled
            onClicked: {
                root.close()
                root.accepted()
            }
        }

        // Right margin
        Item { Layout.preferredWidth: Style.spacingSmall }
    }
}
