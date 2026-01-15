/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

// Warning dialog with icon, title, message, and single action button.
// Extends MessageDialog with a warning icon and centered text.
// Use for important notifications that need visual emphasis (e.g., device removed).
//
// Example usage:
//   WarningDialog {
//       id: storageRemovedDialog
//       imageWriter: window.imageWriter
//       parent: overlayRoot
//       dialogTitle: qsTr("Storage device removed")
//       message: qsTr("The device is no longer available.")
//       buttonText: qsTr("OK")
//       onAccepted: { ... }
//   }
MessageDialog {
    id: root

    // Override default button text
    buttonText: qsTr("OK")

    // Center align title and message for warning dialogs
    titleAlignment: Text.AlignHCenter
    messageAlignment: Text.AlignHCenter

    // Icon customization
    property color iconBackgroundColor: Style.warningTextColor
    property string iconText: "!"
    property int iconSize: 60

    // Warning icon header
    headerContent: Component {
        Rectangle {
            width: root.iconSize
            height: root.iconSize
            radius: root.iconSize / 2
            color: root.iconBackgroundColor

            Text {
                anchors.centerIn: parent
                text: root.iconText
                font.pixelSize: root.iconSize * 0.53
                font.bold: true
                color: "white"
            }

            Accessible.role: Accessible.Graphic
            Accessible.name: qsTr("Warning icon")
        }
    }

    // Override footer to center the button
    footer: RowLayout {
        width: parent ? parent.width : 0
        height: Style.buttonHeightStandard + (Style.cardPadding * 2)
        spacing: Style.spacingMedium

        Item { Layout.preferredWidth: Style.cardPadding }
        Item { Layout.fillWidth: true }

        ImButton {
            text: root.buttonText
            accessibleDescription: root.buttonAccessibleDescription
            Layout.preferredHeight: Style.buttonHeightStandard
            activeFocusOnTab: true
            onClicked: {
                root.close()
                root.accepted()
            }
        }

        Item { Layout.fillWidth: true }
        Item { Layout.preferredWidth: Style.cardPadding }
    }
}
