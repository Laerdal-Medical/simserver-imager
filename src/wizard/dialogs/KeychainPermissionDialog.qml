/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

ConfirmDialog {
    id: root

    property bool userAccepted: false

    function askForPermission() {
        root.userAccepted = false
        open()
    }

    title: qsTr("Keychain Access")
    message: qsTr("Would you like to prefill the Wi‑Fi password from the system keychain?")

    cancelText: CommonStrings.no
    confirmText: CommonStrings.yes
    cancelAccessibleDescription: qsTr("Skip keychain access and manually enter the Wi-Fi password")
    confirmAccessibleDescription: qsTr("Retrieve the Wi-Fi password from the system keychain using administrator authentication")

    // Use destructive styling for the confirm button (red = action)
    destructiveConfirm: true

    // Custom content: sub-text below the message
    Text {
        id: subText
        text: qsTr("This will require administrator authentication on macOS.")
        wrapMode: Text.WordWrap
        color: Style.textMetadataColor
        font.pixelSize: Style.fontSizeSmall
        Layout.fillWidth: true
        Accessible.role: Accessible.StaticText
        Accessible.name: text
        Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
        focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
        activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
    }

    // Track acceptance state
    onAccepted: {
        root.userAccepted = true
    }

    onRejected: {
        root.userAccepted = false
    }

    onClosed: {
        if (!root.userAccepted) {
            root.rejected()
        }
    }
}
