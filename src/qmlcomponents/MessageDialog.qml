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
// Child dialogs can override the footer to provide different button layouts.
//
// Example usage:
//   MessageDialog {
//       id: errorDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       dialogTitle: qsTr("Error")
//       message: "Something went wrong"
//       buttonText: CommonStrings.continueText
//       onAccepted: { ... }
//   }
BaseDialog {
    id: root

    // Dialog content properties
    // Note: Using 'dialogTitle' instead of 'title' because Dialog.title is FINAL
    property string dialogTitle: ""
    property string message: ""
    property string buttonText: CommonStrings.continueText
    property string buttonAccessibleDescription: qsTr("Close this dialog")

    // Title styling (can be overridden by child dialogs)
    property color titleColor: Style.formLabelColor
    property int titleAlignment: Text.AlignLeft

    // Message styling (can be overridden by child dialogs)
    property int messageAlignment: Text.AlignLeft

    // Expose text elements for focus group registration in child dialogs
    property alias titleTextItem: titleText
    property alias messageTextItem: messageText

    // Expose action button for focus group registration
    property alias actionButtonItem: actionButton

    // Optional header content (displayed above title, e.g., warning icon)
    property alias headerContent: headerLoader.sourceComponent

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
                return [titleText, messageText]
            }
            return []
        }, 0)
        registerFocusGroup("buttons", function(){
            return [actionButton]
        }, 1)
    }

    // Optional header content loader (e.g., warning icon)
    Loader {
        id: headerLoader
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        active: sourceComponent !== null
        visible: active
    }

    // Title text
    Text {
        id: titleText
        text: root.dialogTitle
        font.pixelSize: Style.fontSizeHeading
        font.family: Style.fontFamilyBold
        font.bold: true
        color: root.titleColor
        horizontalAlignment: root.titleAlignment
        Layout.fillWidth: true
        visible: text.length > 0
        Accessible.role: Accessible.Heading
        Accessible.name: text
        Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
        focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
        activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
    }

    // Message text
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

    // Footer with action button (can be overridden by child dialogs)
    footer: RowLayout {
        width: parent ? parent.width : 0
        height: Style.buttonHeightStandard + (Style.cardPadding * 2)
        spacing: Style.spacingMedium

        Item { Layout.preferredWidth: Style.cardPadding }
        Item { Layout.fillWidth: true }

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
