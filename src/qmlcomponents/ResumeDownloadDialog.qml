/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

/**
 * Dialog shown on startup when a partial download is detected.
 * Allows the user to resume or discard the incomplete download.
 */
BaseDialog {
    id: root

    required property var imageWriter

    title: qsTr("Resume Download?")

    // Partial download info (set from imageWriter.getPartialDownloadInfo())
    property var downloadInfo: ({})

    // Computed display values
    readonly property string displayName: downloadInfo.displayName || qsTr("Unknown")
    readonly property int percentComplete: Math.round(downloadInfo.percentComplete || 0)
    readonly property string bytesDownloaded: imageWriter ? imageWriter.formatSize(downloadInfo.bytesDownloaded || 0) : "0"
    readonly property string totalSize: imageWriter ? imageWriter.formatSize(downloadInfo.totalSize || 0) : "0"

    // Signals
    signal resumeRequested()
    signal discardRequested()

    // Override width for this dialog
    implicitWidth: 450

    // Prevent closing by clicking outside
    closePolicy: Popup.CloseOnEscape

    ColumnLayout {
        spacing: Style.spacingMedium
        Layout.fillWidth: true

        Text {
            text: qsTr("A previous download was interrupted:")
            color: Style.formLabelColor
            font.pixelSize: Style.fontSizeSm
            font.family: Style.fontFamily
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Image/download name
        Text {
            text: root.displayName
            color: Style.formLabelColor
            font.pixelSize: Style.fontSizeMd
            font.family: Style.fontFamily
            font.bold: true
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }

        // Progress indicator
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            ProgressBar {
                id: progressBar
                anchors.fill: parent
                from: 0
                to: 100
                value: root.percentComplete

                background: Rectangle {
                    implicitWidth: 200
                    implicitHeight: 28
                    color: Style.progressBarTrackColor
                    radius: 4
                }

                contentItem: Item {
                    implicitWidth: 200
                    implicitHeight: 26

                    Rectangle {
                        width: progressBar.visualPosition * parent.width
                        height: parent.height
                        radius: 4
                        color: Style.laerdalBlue
                    }
                }
            }

            // Progress text centered over the bar
            Text {
                anchors.centerIn: parent
                text: qsTr("%1% complete").arg(root.percentComplete)
                color: Style.formLabelColor
                font.pixelSize: Style.fontSizeSm
                font.family: Style.fontFamily
                font.bold: true
            }
        }

        // Size info
        Text {
            text: qsTr("%1 of %2 downloaded").arg(root.bytesDownloaded).arg(root.totalSize)
            color: Style.textMetadataColor
            font.pixelSize: Style.fontSizeXs
            font.family: Style.fontFamily
            Layout.fillWidth: true
        }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacingMedium

            ImButton {
                id: discardButton
                text: qsTr("Discard")
                onClicked: {
                    root.discardRequested()
                    root.close()
                }
            }

            Item { Layout.fillWidth: true }

            ImButton {
                id: resumeButton
                text: qsTr("Resume")
                highlighted: true
                onClicked: {
                    root.resumeRequested()
                    root.close()
                }
            }
        }
    }

    // Handle escape key - treat as discard
    function escapePressed() {
        root.discardRequested()
        root.close()
    }

    onOpened: {
        resumeButton.forceActiveFocus()
    }

    Component.onCompleted: {
        registerFocusGroup("buttons", function() { return [discardButton, resumeButton] }, 0)
    }
}
