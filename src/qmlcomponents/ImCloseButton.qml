
/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Layouts

import RpiImager

Text {
    id: root
    signal clicked

    // Set to false when using inside a Layout to avoid anchor conflicts
    property bool useAnchors: true

    text: "X"

    // Default alignment for Layout contexts
    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    // Anchors for non-Layout contexts (e.g., inside Rectangle)
    anchors.right: useAnchors ? parent.right : undefined
    anchors.top: useAnchors ? parent.top : undefined
    anchors.rightMargin: useAnchors ? 25 : 0
    anchors.topMargin: useAnchors ? 10 : 0

    font.family: Style.fontFamily
    font.bold: true
    
    // Accessibility properties
    Accessible.role: Accessible.Button
    Accessible.name: "Close"
    Accessible.description: "Close dialog"
    Accessible.onPressAction: root.clicked()
    
    // Make it keyboard accessible
    focus: true
    activeFocusOnTab: true
    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.clicked();
        }
    }
}
