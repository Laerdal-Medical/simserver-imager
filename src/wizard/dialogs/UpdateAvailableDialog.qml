/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

ConfirmDialog {
    id: root

    // For overlay parenting set by caller if needed
    property alias overlayParent: root.parent

    property url url

    title: qsTr("Update available")
    message: qsTr("There is a newer version of Imager available. Would you like to visit the website to download it?")

    cancelText: CommonStrings.no
    confirmText: CommonStrings.yes
    cancelAccessibleDescription: qsTr("Continue using the current version of Laerdal SimServer Imager")
    confirmAccessibleDescription: qsTr("Open the Laerdal website in your browser to download the latest version")

    // Use destructive styling for the confirm button (red = action)
    destructiveConfirm: true

    // Open URL when accepted
    onAccepted: {
        if (root.url && root.url.toString && root.url.toString().length > 0) {
            if (root.imageWriter) {
                root.imageWriter.openUrl(root.url)
            } else {
                Qt.openUrlExternally(root.url)
            }
        }
    }
}
