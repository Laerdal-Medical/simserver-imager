/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

/**
 * Dialog showing download progress for CI artifact inspection.
 */
BaseDialog {
    id: root

    required property var imageWriter

    title: qsTr("Downloading CI Build")

    // Progress values
    property real progress: 0  // 0.0 to 1.0
    property string artifactName: ""
    property bool indeterminate: false

    // Signal emitted when user cancels download
    signal cancelled()

    // Computed display values
    readonly property int progressPercent: Math.round(progress * 100)

    // Override width for this dialog
    implicitWidth: 450
    implicitHeight: 235

    // Allow closing with Escape key (which triggers cancel)
    closePolicy: Popup.CloseOnEscape

    ColumnLayout {
        spacing: Style.spacingMedium
        Layout.fillWidth: true

        Text {
            text: qsTr("Downloading artifact to inspect contents...")
            color: Style.formLabelColor
            font.pixelSize: Style.fontSizeSm
            font.family: Style.fontFamily
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Text {
            text: root.artifactName
            color: Style.textMetadataColor
            font.pixelSize: Style.fontSizeXs
            font.family: Style.fontFamily
            font.italic: true
            elide: Text.ElideMiddle
            Layout.fillWidth: true
            visible: root.artifactName.length > 0
        }

        // Progress bar container with text overlay
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            ProgressBar {
                id: progressBar
                anchors.fill: parent
                from: 0
                to: 1
                value: root.indeterminate ? 0 : root.progress
                indeterminate: root.indeterminate

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
                        id: progressFill
                        x: 0
                        width: root.indeterminate ? parent.width * 0.3 : progressBar.visualPosition * parent.width
                        height: parent.height
                        radius: 4
                        color: Style.laerdalBlue

                        // Reset x when switching from indeterminate to determinate
                        onWidthChanged: {
                            if (!root.indeterminate) {
                                x = 0
                            }
                        }

                        // Animation for indeterminate mode
                        SequentialAnimation {
                            id: indeterminateAnimation
                            running: root.indeterminate && root.visible
                            loops: Animation.Infinite

                            // Reset position when animation stops
                            onRunningChanged: {
                                if (!running) {
                                    progressFill.x = 0
                                }
                            }

                            NumberAnimation {
                                target: progressFill
                                property: "x"
                                from: 0
                                to: progressBar.width * 0.7
                                duration: 1000
                                easing.type: Easing.InOutQuad
                            }
                            NumberAnimation {
                                target: progressFill
                                property: "x"
                                from: progressBar.width * 0.7
                                to: 0
                                duration: 1000
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }
            }

            // Progress text centered over the bar
            Text {
                anchors.centerIn: parent
                text: root.indeterminate ? qsTr("Connecting...") : qsTr("%1%").arg(root.progressPercent)
                color: Style.formLabelColor
                font.pixelSize: Style.fontSizeSm
                font.family: Style.fontFamily
                font.bold: true
            }
        }

        // Cancel button
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacingSmall

            Item { Layout.fillWidth: true }

            ImButton {
                id: cancelButton
                text: qsTr("Cancel")
                onClicked: {
                    root.cancelled()
                    root.close()
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    // Reset progress when dialog opens
    onOpened: {
        root.progress = 0
        root.indeterminate = true
        cancelButton.forceActiveFocus()
    }

    // Handle escape key
    function escapePressed() {
        root.cancelled()
        root.close()
    }

    Component.onCompleted: {
        registerFocusGroup("buttons", function() { return [cancelButton] }, 0)
    }
}
