/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

/**
 * Dialog for selecting an image file from a CI artifact that contains multiple installable files.
 * Supports both WIC (disk images) and SPU (firmware update) files.
 */
BaseDialog {
    id: root

    required property var imageWriter

    title: qsTr("Select Image File")

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

    ColumnLayout {
        spacing: Style.spacingMedium
        Layout.fillWidth: true

        Text {
            text: qsTr("This CI build contains multiple installable images. Please select which one to use:")
            color: Style.formLabelColor
            font.pixelSize: Style.fontSizeSm
            font.family: Style.fontFamily
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Text {
            text: artifactName
            color: Style.textMetadataColor
            font.pixelSize: Style.fontSizeXs
            font.family: Style.fontFamily
            font.italic: true
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            visible: artifactName.length > 0
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(300, fileListView.contentHeight + 4)
            color: Style.mainBackgroundColor
            radius: Style.sectionBorderRadius
            border.color: Style.popupBorderColor
            border.width: Style.sectionBorderWidth

            ListView {
                id: fileListView
                anchors.fill: parent
                anchors.margins: 2
                model: root.imageFiles
                clip: true
                currentIndex: 0

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: ItemDelegate {
                    id: fileDelegate
                    width: fileListView.width
                    height: 60
                    highlighted: fileListView.currentIndex === index

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
                                text: modelData.display_name || modelData.filename
                                color: fileDelegate.highlighted ? "white" : Style.formLabelColor
                                font.pixelSize: Style.fontSizeSm
                                font.family: Style.fontFamily
                                font.bold: true
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            // File type badge
                            ImBadge {
                                type: modelData.type === "spu" ? "spu" : (modelData.type === "vsi" ? "vsi" : "wic")
                            }
                        }

                        Text {
                            text: modelData.filename !== modelData.display_name ? modelData.filename : ""
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
                                    var bytes = modelData.size || 0
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
                                text: modelData.type === "spu" ? qsTr("(Firmware Update)") :
                                      (modelData.type === "vsi" ? qsTr("(Versioned Sparse Image)") : qsTr("(Disk Image)"))
                                color: fileDelegate.highlighted ? Qt.rgba(1,1,1,0.5) : Style.textDescriptionColor
                                font.pixelSize: Style.fontSizeXs
                                font.family: Style.fontFamily
                                font.italic: true
                            }
                        }
                    }

                    onClicked: {
                        fileListView.currentIndex = index
                    }

                    onDoubleClicked: {
                        fileListView.currentIndex = index
                        root.selectCurrentFile()
                    }
                }

                Keys.onReturnPressed: root.selectCurrentFile()
                Keys.onEnterPressed: root.selectCurrentFile()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingMedium

            Item { Layout.fillWidth: true }

            ImButton {
                text: qsTr("Cancel")
                onClicked: {
                    root.cancelled()
                    root.close()
                }
            }

            ImButton {
                text: qsTr("Select")
                highlighted: true
                enabled: fileListView.currentIndex >= 0 && root.imageFiles.length > 0
                onClicked: root.selectCurrentFile()
            }
        }
    }

    function selectCurrentFile() {
        if (fileListView.currentIndex >= 0 && fileListView.currentIndex < root.imageFiles.length) {
            var file = root.imageFiles[fileListView.currentIndex]
            root.fileSelected(file.filename, file.display_name || file.filename, file.size || 0, file.type || "wic")
            root.close()
        }
    }

    onOpened: {
        fileListView.forceActiveFocus()
    }

    Component.onCompleted: {
        registerFocusGroup("file_list", function() { return [fileListView] }, 0)
    }
}
