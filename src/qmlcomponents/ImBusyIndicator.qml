/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import RpiImager

// Laerdal-styled busy indicator using brand colors
BusyIndicator {
    id: control

    property real spinnerSize: 40
    property real strokeWidth: 4

    contentItem: Item {
        implicitWidth: 48
        implicitHeight: 48

        // Spinning arc indicator
        Item {
            id: spinner
            anchors.centerIn: parent
            width: control.spinnerSize
            height: control.spinnerSize

            // Background circle (track)
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: control.strokeWidth
                border.color: Style.cardBackground
            }

            // Spinning arc using Canvas
            Canvas {
                id: arcCanvas
                anchors.fill: parent
                antialiasing: true

                property real arcLength: 0.25  // Length of arc (0-1)
                property real rotation: 0

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()

                    var centerX = width / 2
                    var centerY = height / 2
                    var radius = width / 2 - control.strokeWidth / 2

                    ctx.strokeStyle = Style.laerdalBlue
                    ctx.lineWidth = control.strokeWidth
                    ctx.lineCap = "round"

                    ctx.beginPath()
                    var startAngle = rotation * Math.PI * 2 - Math.PI / 2
                    var endAngle = startAngle + arcLength * Math.PI * 2
                    ctx.arc(centerX, centerY, radius, startAngle, endAngle)
                    ctx.stroke()
                }

                // Animation for spinning
                RotationAnimation on rotation {
                    from: 0
                    to: 1
                    duration: 1000
                    loops: Animation.Infinite
                    running: control.running
                }

                // Redraw when rotation changes
                Connections {
                    target: arcCanvas
                    function onRotationChanged() {
                        arcCanvas.requestPaint()
                    }
                }

                Component.onCompleted: requestPaint()
            }
        }
    }
}
