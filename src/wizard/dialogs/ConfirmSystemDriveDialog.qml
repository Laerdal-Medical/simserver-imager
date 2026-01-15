// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2025 Raspberry Pi Ltd
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

WarningDialog {
    id: root

    // Override positioning for overlayParent support
    required property Item overlayParent
    parent: overlayParent
    anchors.centerIn: parent

    property string driveName: ""
    property string device: ""
    property real deviceSize: 0
    property string sizeStr: ""
    property var mountpoints: []

    signal confirmed()
    signal cancelled()

    readonly property string riskText: CommonStrings.warningRiskText
    readonly property string proceedText: CommonStrings.warningProceedText
    readonly property string systemDriveText: CommonStrings.systemDriveText

    // Use the message property for warning text
    message: root.riskText + "<br><br>" + root.systemDriveText + "<br><br>" + root.proceedText

    // Primary button continues (confirms the action)
    buttonText: qsTr("CONTINUE")
    buttonAccessibleDescription: qsTr("Proceed to write the image to this system drive after confirming the drive name")

    // Override escape handling to emit cancelled
    function escapePressed() {
        root.close()
        root.cancelled()
    }

    // Add cancel button before the primary button
    footerButtons: [
        ImButtonRed {
            id: cancelButton
            text: qsTr("CANCEL")
            accessibleDescription: qsTr("Cancel operation and return to storage selection to choose a different device")
            onClicked: {
                root.close()
                root.cancelled()
            }
        }
    ]

    // Override focus groups for custom layout
    Component.onCompleted: {
        registerFocusGroup("content", function(){
            // Only include text elements when screen reader is active
            if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                return [messageTextItem, driveNameText]
            }
            return []
        }, 0)
        registerFocusGroup("input", function(){
            return [nameInput]
        }, 1)
        registerFocusGroup("buttons", function(){
            return [cancelButton, root.actionButtonItem]
        }, 2)
    }

    onOpened: {
        nameInput.text = ""
        // Let BaseDialog handle the focus management through the focus groups
    }

    // Connect to accepted signal to emit confirmed
    onAccepted: root.confirmed()

    // Custom content below the message
    Rectangle { implicitHeight: 1; Layout.fillWidth: true; color: Style.titleSeparatorColor; Accessible.ignored: true }

    ColumnLayout {
        Layout.fillWidth: true
        Accessible.role: Accessible.Grouping
        Accessible.name: qsTr("Drive information")
        Text {
            text: qsTr("Size: %1").arg(root.sizeStr)
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
        Text {
            text: qsTr("Mounted as: %1").arg(root.mountpoints && root.mountpoints.length > 0 ? root.mountpoints.join(", ") : qsTr("Not mounted"))
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }

    Rectangle { implicitHeight: 1; Layout.fillWidth: true; color: Style.titleSeparatorColor; Accessible.ignored: true }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.family: Style.fontFamily
        font.pixelSize: Style.fontSizeDescription
        color: Style.textDescriptionColor
        text: qsTr("To continue, type the exact drive name below:")
        Accessible.role: Accessible.StaticText
        Accessible.name: text
        Accessible.ignored: false
    }

    Text {
        id: driveNameText
        font.family: Style.fontFamily
        font.bold: true
        color: Style.textDescriptionColor
        text: root.driveName
        // Make this text focusable when screen reader is active
        Accessible.role: Accessible.StaticText
        Accessible.name: qsTr("Drive name to type: %1").arg(text)
        Accessible.ignored: false
        Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
        focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
        activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
    }

    TextField {
        id: nameInput
        Layout.fillWidth: true
        placeholderText: qsTr("Type drive name exactly as shown above")
        text: ""
        activeFocusOnTab: true
        // Combine all information in the name for VoiceOver
        Accessible.name: qsTr("Drive name input. Type exactly: %1. %2").arg(root.driveName).arg(placeholderText)
        Accessible.description: ""
        Keys.onPressed: (event) => {
            if ((event.key === Qt.Key_V && (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) ||
                (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) {
                event.accepted = true
                return
            }
        }
        onAccepted: {
            if (root.actionButtonItem.enabled) root.actionButtonItem.clicked()
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton | Qt.MiddleButton
            onPressed: (mouse) => { mouse.accepted = true }
        }

        // Enable/disable the primary button based on input validation
        onTextChanged: {
            root.actionButtonItem.enabled = (text === root.driveName)
        }
    }
}
