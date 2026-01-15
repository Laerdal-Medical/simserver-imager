// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2025 Raspberry Pi Ltd

import QtQuick
import QtQuick.Controls
import RpiImager

WarningDialog {
    id: root

    // Override positioning for overlayParent support
    closePolicy: Popup.CloseOnEscape
    required property Item overlayParent
    parent: overlayParent
    anchors.centerIn: parent

    signal confirmed()
    signal cancelled()

    readonly property string riskText: CommonStrings.warningRiskText
    readonly property string proceedText: CommonStrings.warningProceedText
    readonly property string systemDriveText: CommonStrings.systemDriveText

    title: qsTr("Show system drives?")

    // Use the message property for warning text
    message: qsTr("By disabling system drive filtering, <b>system drives will be shown</b> in the list.")
          + "<br><br>"
          + root.systemDriveText
          + "<br><br>" + root.riskText + "<br><br>" + root.proceedText

    // Primary button shows system drives (confirms the action)
    buttonText: qsTr("SHOW SYSTEM DRIVES")
    buttonAccessibleDescription: qsTr("Remove the safety filter and display system drives in the storage device list")

    // Override escape handling to emit cancelled
    function escapePressed() {
        root.close()
        root.cancelled()
    }

    // Add cancel button (keep filter on) before the primary button
    footerButtons: [
        ImButtonRed {
            id: keepFilterButton
            text: qsTr("KEEP FILTER ON")
            accessibleDescription: qsTr("Keep system drives hidden to prevent accidental damage to your operating system")
            // Allow button to grow to fit text for this important warning dialog
            implicitWidth: Math.max(Style.buttonWidthMinimum, implicitContentWidth + leftPadding + rightPadding)
            onClicked: {
                root.close()
                root.cancelled()
            }
        }
    ]

    // Override focus groups for custom button layout
    Component.onCompleted: {
        registerFocusGroup("content", function(){
            // Only include message text when screen reader is active
            return (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? [messageTextItem] : []
        }, 0)
        registerFocusGroup("buttons", function(){
            return [keepFilterButton, root.actionButtonItem]
        }, 1)
    }

    // Connect to accepted signal to emit confirmed
    onAccepted: root.confirmed()
}
