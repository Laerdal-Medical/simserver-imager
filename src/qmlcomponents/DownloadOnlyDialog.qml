/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 Laerdal Medical
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import RpiImager

BaseDialog {
    id: root
    required property ImageWriter writer
    imageWriter: root.writer
    readonly property DownloadOnly transfer: root.writer.downloadOnly
    property var source: ({})
    property url destination: ""

    title: qsTr("Download only")
    closePolicy: root.transfer.busy ? Popup.NoAutoClose : Popup.CloseOnEscape

    function choose(sourceInfo) {
        if (root.transfer.busy) return
        root.source = sourceInfo
        saveDialog.suggestedFilename = root.transfer.suggestedFilename(sourceInfo)
        saveDialog.open()
    }

    function start(overwrite) {
        root.writer.startDownloadOnly(root.source, root.destination, overwrite)
        root.open()
    }

    function escapePressed() {
        if (root.transfer.busy) root.transfer.cancel()
        else root.close()
    }

    ImSaveFileDialog {
        id: saveDialog
        imageWriter: root.writer
        parent: root.parent
        dialogTitle: qsTr("Save original image")
        currentFolder: (Qt.platform.os === "windows" ? "file:///" : "file://")
                       + StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        nameFilters: [qsTr("All files (*)")]
        onAccepted: {
            root.destination = saveDialog.selectedFile
            if (root.transfer.destinationExists(root.destination)) overwriteDialog.open()
            else root.start(false)
        }
    }

    ConfirmDialog {
        id: overwriteDialog
        imageWriter: root.writer
        parent: root.parent
        title: qsTr("Replace existing file?")
        message: qsTr("The destination already exists. Replace it only after the download completes successfully?")
        confirmText: qsTr("Replace")
        cancelText: CommonStrings.cancel
        onAccepted: root.start(true)
    }

    Label {
        Layout.fillWidth: true
        text: root.transfer.status
        wrapMode: Text.Wrap
    }
    ImProgressBar {
        Layout.fillWidth: true
        visible: root.transfer.busy
        from: 0
        to: 1
        value: root.transfer.total > 0 ? root.transfer.received / root.transfer.total : 0
        indeterminate: root.transfer.total <= 0
    }
    Label {
        Layout.fillWidth: true
        visible: root.transfer.busy
        text: root.transfer.total > 0
              ? qsTr("%1 / %2").arg(Utils.formatBytes(root.transfer.received)).arg(Utils.formatBytes(root.transfer.total))
              : Utils.formatBytes(root.transfer.received)
    }
    Label {
        Layout.fillWidth: true
        visible: root.transfer.error.length > 0
        text: root.transfer.error
        color: Style.warningTextColor
        wrapMode: Text.Wrap
    }
    Label {
        Layout.fillWidth: true
        visible: String(root.transfer.savedFile).length > 0
        text: String(root.transfer.savedFile)
        wrapMode: Text.WrapAnywhere
    }
    RowLayout {
        Layout.fillWidth: true
        ImButton {
            text: qsTr("Open containing folder")
            Layout.minimumWidth: Style.buttonWidthMinimum * 2
            visible: !root.transfer.busy && String(root.transfer.savedFile).length > 0
            onClicked: root.transfer.openContainingFolder()
        }
        Item { Layout.fillWidth: true }
        ImButton {
            text: root.transfer.busy ? CommonStrings.cancel : qsTr("Close")
            onClicked: {
                if (root.transfer.busy) root.transfer.cancel()
                else root.close()
            }
        }
    }
}
