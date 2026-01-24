/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RpiImager

// Reusable progress bar component with Laerdal brand styling
ColumnLayout {
    id: root

    // Progress bar properties
    property alias value: progressBar.value
    property alias from: progressBar.from
    property alias to: progressBar.to
    property alias indeterminate: progressBar.indeterminate

    // Text label above the bar
    property bool showText: false
    property string indeterminateText: qsTr("Progress indeterminate")
    property string text: qsTr("Progress... %1%").arg(Math.round((root.value - root.from) / (root.to - root.from) * 100))
    property color textColor: Style.formLabelColor

    // Color customization
    property color fillColor: Style.laerdalBlue
    property color trackColor: Style.progressBarTrackColor

    spacing: Style.spacingMedium

    // Text label above the progress bar
    Text {
        id: textLabel
        Layout.alignment: Qt.AlignHCenter
        visible: root.showText
        text: root.indeterminate ? root.indeterminateText : root.text
        color: root.textColor
        font.pixelSize: Style.fontSizeProgressBar
        font.family: Style.fontFamilyBold
        font.bold: true
    }

    // Progress bar track
    Rectangle {
        id: bar
        Layout.fillWidth: true
        implicitHeight: 28
        color: root.trackColor
        radius: 8
        border.width: 2
        border.color: '#1c2e7ea1'

        ProgressBar {
            id: progressBar
            anchors.fill: parent
            anchors.margins: 2

            background: Item {
                // Transparent - the outer Rectangle provides the background
            }

            contentItem: Item {
                implicitWidth: 196
                implicitHeight: 24

                Rectangle {
                    id: progressFill
                    property real animProgress: 1.0
                    x: root.indeterminate ? animProgress * (parent.width - width) : 0
                    width: root.indeterminate ? parent.width * 0.3 : progressBar.visualPosition * parent.width
                    height: parent.height
                    radius: 6
                    color: root.fillColor

                    // Smooth the fill width between progress updates.
                    // With 1MB write blocks, completions arrive every ~33ms at 30MB/s.
                    // A 150ms linear animation creates smooth overlap between updates,
                    // eliminating the discrete jumps that cause perceived stuttering.
                    Behavior on width {
                        enabled: !root.indeterminate
                        NumberAnimation { duration: 150; easing.type: Easing.Linear }
                    }

                    // Animation for indeterminate mode - starts from right
                    SequentialAnimation {
                        id: indeterminateAnimation
                        running: root.indeterminate && root.visible
                        loops: Animation.Infinite

                        onRunningChanged: {
                            if (!running) {
                                progressFill.animProgress = 1.0
                            }
                        }

                        NumberAnimation {
                            target: progressFill
                            property: "animProgress"
                            from: 1; to: 0
                            duration: 1000
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            target: progressFill
                            property: "animProgress"
                            from: 0; to: 1
                            duration: 1000
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
        }
    }

    // Accessibility
    Accessible.role: Accessible.ProgressBar
    Accessible.name: root.indeterminate ? root.indeterminateText : root.text
}
