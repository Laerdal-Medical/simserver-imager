/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

/**
 * Dialog for selecting an image file from a CI artifact that contains multiple installable files.
 * Supports both WIC (disk images) and SPU (firmware update) files.
 */
ConfirmDialog {
    id: root

    required property var imageWriter

    title: qsTr("Select Image File")
    message: qsTr("This CI build contains multiple installable images. Please select which one to use:")

    cancelText: qsTr("Cancel")
    confirmText: qsTr("Select")
    cancelAccessibleDescription: qsTr("Cancel and close this dialog")
    confirmAccessibleDescription: qsTr("Select the highlighted image file")

    // Use normal (non-destructive) styling for Select button
    destructiveConfirm: false

    // Artifact metadata
    // Using var/double to support GitHub artifact IDs > 2^31 (JavaScript's safe integer range is 2^53)
    property var artifactId: 0
    property string artifactName: ""
    property string owner: ""
    property string repo: ""
    property string branch: ""
    property string zipPath: ""

    // List of image files found in the artifact
    // Each item: { filename: string, display_name: string, size: int, type: "wic"|"spu" }
    property var imageFiles: []

    // Legacy alias for backwards compatibility
    property alias wicFiles: root.imageFiles

    // Signal emitted when user selects a file
    // type is "wic" or "spu"
    signal fileSelected(string filename, string displayName, int size, string fileType)
    signal cancelled()

    // Override width for this dialog
    implicitWidth: 500

    // Handle accepted - emit fileSelected with current selection
    onAccepted: {
        if (fileListView.currentIndex >= 0 && fileListView.currentIndex < root.imageFiles.length) {
            var file = root.imageFiles[fileListView.currentIndex]
            root.fileSelected(file.filename, file.display_name || file.filename, file.size || 0, file.type || "wic")
        }
    }

    // Handle rejected - emit cancelled
    onRejected: {
        root.cancelled()
    }

    // Custom content: artifact name and file list
    Text {
        text: root.artifactName
        color: Style.textMetadataColor
        font.pixelSize: Style.fontSizeXs
        font.family: Style.fontFamily
        font.italic: true
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        visible: root.artifactName.length > 0
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(300, fileListView.contentHeight)
        color: Style.mainBackgroundColor
        radius: Style.sectionBorderRadius
        border.color: Style.popupBorderColor
        border.width: Style.sectionBorderWidth

        ListView {
            id: fileListView
            anchors.fill: parent
            anchors.margins: Style.spacingXXSmall
            model: root.imageFiles
            clip: true
            currentIndex: 0

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: ItemDelegate {
                id: fileDelegate
                required property int index
                required property var modelData
                property var dialogRoot: root
                width: ListView.view.width
                height: 60
                highlighted: ListView.view.currentIndex === fileDelegate.index

                background: Rectangle {
                    color: fileDelegate.highlighted ? Style.laerdalBlue :
                           (fileDelegate.hovered ? Style.listViewHoverRowBackgroundColor : "transparent")
                    radius: Style.listItemBorderRadius
                }

                contentItem: ColumnLayout {
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall

                        Text {
                            text: fileDelegate.modelData.display_name || fileDelegate.modelData.filename
                            color: fileDelegate.highlighted ? "white" : Style.formLabelColor
                            font.pixelSize: Style.fontSizeSm
                            font.family: Style.fontFamily
                            font.bold: true
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }

                        // File type badge
                        ImBadge {
                            type: fileDelegate.modelData.type === "spu" ? "spu" : (fileDelegate.modelData.type === "vsi" ? "vsi" : "wic")
                        }
                    }

                    Text {
                        text: fileDelegate.modelData.filename !== fileDelegate.modelData.display_name ? fileDelegate.modelData.filename : ""
                        color: fileDelegate.highlighted ? Qt.rgba(1,1,1,0.7) : Style.textMetadataColor
                        font.pixelSize: Style.fontSizeXs
                        font.family: Style.fontFamily
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        visible: text.length > 0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall

                        Text {
                            property string sizeStr: {
                                var bytes = fileDelegate.modelData.size || 0
                                if (bytes < 1024) return bytes + " B"
                                if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
                                if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB"
                                return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB"
                            }
                            text: qsTr("Size: %1").arg(sizeStr)
                            color: fileDelegate.highlighted ? Qt.rgba(1,1,1,0.7) : Style.textMetadataColor
                            font.pixelSize: Style.fontSizeXs
                            font.family: Style.fontFamily
                        }

                        Text {
                            text: fileDelegate.modelData.type === "spu" ? qsTr("(Firmware Update)") :
                                  (fileDelegate.modelData.type === "vsi" ? qsTr("(Versioned Sparse Image)") : qsTr("(Disk Image)"))
                            color: fileDelegate.highlighted ? Qt.rgba(1,1,1,0.5) : Style.textDescriptionColor
                            font.pixelSize: Style.fontSizeXs
                            font.family: Style.fontFamily
                            font.italic: true
                        }
                    }
                }

                onClicked: {
                    ListView.view.currentIndex = fileDelegate.index
                }

                onDoubleClicked: {
                    ListView.view.currentIndex = fileDelegate.index
                    fileDelegate.dialogRoot.accept()
                }

                // Touch support - double tap to select
                TapHandler {
                    onDoubleTapped: fileDelegate.doubleClicked()
                }
            }

            Keys.onReturnPressed: root.accept()
            Keys.onEnterPressed: root.accept()
        }
    }

    onOpened: {
        fileListView.forceActiveFocus()
    }
}
