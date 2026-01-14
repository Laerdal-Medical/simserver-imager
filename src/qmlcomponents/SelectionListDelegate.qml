/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import RpiImager

/*
 * A reusable delegate for SelectionListView that provides consistent styling
 * for list items with icon, title, description, and optional badges/metadata.
 *
 * Usage:
 *   SelectionListView {
 *       delegate: SelectionListDelegate {
 *           itemTitle: model.name
 *           itemDescription: model.description
 *           itemIcon: model.icon
 *           // Optional: add custom content (badges, etc.) as children
 *           badges: [{ type: "ci" }, { type: "wic" }]
 *       }
 *   }
 */
Item {
    id: root

    // The delegate index from the model. When used inside a Component wrapper,
    // the outer delegate should declare `required property int index` and bind
    // it here: `delegateIndex: outerDelegate.index`
    property int delegateIndex: -1
    property var parentListView: ListView.view

    // Core content properties
    property string itemTitle: ""
    property string itemDescription: ""
    property string itemIcon: ""  // URL/path to icon image
    property string itemEmoji: "" // Alternative: emoji character instead of icon

    // Optional metadata lines (shown below description)
    property string itemMetadata: ""      // Primary metadata (e.g., size, status)
    property string itemMetadata2: ""     // Secondary metadata (e.g., release date)

    // Badge support (shown next to title)
    // Array of {text: string, variant: string} objects where variant is an ImBadge color variant
    property var badges: []

    // Selection state (for special highlighting like "selected SPU file")
    property bool isItemSelected: false
    property color selectedBackgroundColor: Style.laerdalBlue
    property color selectedTextColor: "white"

    // Disabled/unselectable state (for read-only items)
    property bool isDisabled: false
    property string disabledReason: ""  // e.g., "Read-only"

    // Hidden state (for filtered items)
    property bool isHidden: false

    // Show arrow indicator for items that navigate to sublists
    property bool showArrow: false

    // Minimum height
    property int minimumHeight: 60

    // Icon size
    property int iconSize: 40

    // Sizing
    width: parentListView ? parentListView.width : 200
    height: isHidden ? 0 : Math.max(minimumHeight, contentRow.implicitHeight + Style.spacingSmall + Style.spacingMedium)
    visible: !isHidden

    // Accessibility
    Accessible.role: Accessible.ListItem
    Accessible.name: itemTitle + (itemDescription ? ". " + itemDescription : "") + (itemMetadata ? ". " + itemMetadata : "") + (isDisabled && disabledReason ? ". " + disabledReason : "")
    Accessible.focusable: true
    Accessible.ignored: false

    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        anchors.rightMargin: (parentListView && parentListView.contentHeight > parentListView.height) ? Style.scrollBarWidth : 0

        color: root.isItemSelected ? root.selectedBackgroundColor
             : (parentListView && parentListView.currentIndex === root.delegateIndex) ? Style.listViewHighlightColor
             : (mouseArea.containsMouse && !root.isDisabled ? Style.listViewHoverRowBackgroundColor : Style.listViewRowBackgroundColor)
        radius: 0
        opacity: root.isDisabled ? 0.5 : 1.0
        Accessible.ignored: true

        RowLayout {
            id: contentRow
            anchors.fill: parent
            anchors.leftMargin: Style.listItemPadding
            anchors.rightMargin: Style.listItemPadding
            anchors.topMargin: Style.spacingSmall
            anchors.bottomMargin: Style.spacingMedium
            spacing: Style.spacingMedium

            // Emoji icon (alternative to image icon)
            Text {
                id: emojiIcon
                text: root.itemEmoji
                font.pixelSize: root.iconSize * 0.8
                visible: root.itemEmoji !== "" && root.itemIcon === ""
                Layout.alignment: Qt.AlignVCenter
            }

            // Image icon
            Image {
                id: imageIcon
                source: root.itemIcon
                cache: true
                asynchronous: true
                Layout.preferredWidth: root.iconSize
                Layout.preferredHeight: root.iconSize
                Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                sourceSize: Qt.size(Math.round(Layout.preferredWidth * Screen.devicePixelRatio),
                                    Math.round(Layout.preferredHeight * Screen.devicePixelRatio))
                visible: root.itemIcon !== ""

                // Fallback border when image fails to load
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.color: Style.titleSeparatorColor
                    border.width: 1
                    radius: 0
                    visible: parent.status === Image.Error
                }
            }

            // Text content
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacingXXSmall

                // Title row with badges
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingSmall

                    Text {
                        id: titleText
                        text: root.itemTitle
                        font.pixelSize: Style.fontSizeFormLabel
                        font.family: Style.fontFamilyBold
                        font.bold: true
                        color: root.isDisabled ? Style.formLabelDisabledColor
                             : root.isItemSelected ? root.selectedTextColor
                             : Style.formLabelColor
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        Accessible.ignored: true
                    }

                    // Badges from badges property array
                    Repeater {
                        model: root.badges

                        ImBadge {
                            required property var modelData
                            required property int index
                            type: modelData.type || ""
                            visible: type.length > 0
                        }
                    }
                }

                // Description
                Text {
                    text: root.itemDescription
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: root.isDisabled ? Style.formLabelDisabledColor
                         : root.isItemSelected ? root.selectedTextColor
                         : Style.textDescriptionColor
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: root.itemDescription !== ""
                    Accessible.ignored: true
                }

                // Primary metadata line
                Text {
                    text: root.itemMetadata
                    font.pixelSize: Style.fontSizeCaption
                    font.family: Style.fontFamily
                    color: root.isDisabled ? Style.formLabelDisabledColor
                         : root.isItemSelected ? root.selectedTextColor
                         : Style.textMetadataColor
                    Layout.fillWidth: true
                    visible: root.itemMetadata !== ""
                    Accessible.ignored: true
                }

                // Secondary metadata line
                Text {
                    text: root.itemMetadata2
                    font.pixelSize: Style.fontSizeSmall
                    font.family: Style.fontFamily
                    color: root.isDisabled ? Style.formLabelDisabledColor
                         : root.isItemSelected ? root.selectedTextColor
                         : Style.textMetadataColor
                    Layout.fillWidth: true
                    visible: root.itemMetadata2 !== ""
                    Accessible.ignored: true
                }
            }

            // Disabled reason indicator (e.g., "Read-only")
            Text {
                text: root.disabledReason
                font.pixelSize: Style.fontSizeDescription
                font.family: Style.fontFamily
                color: Style.formLabelErrorColor
                visible: root.isDisabled && root.disabledReason !== ""
                Layout.alignment: Qt.AlignVCenter
                Accessible.ignored: true
            }

            // Arrow indicator for sublists
            Text {
                text: "›"
                font.pixelSize: Style.fontSizeHeading
                font.family: Style.fontFamily
                color: root.isItemSelected ? root.selectedTextColor : Style.textDescriptionColor
                visible: root.showArrow
                Layout.alignment: Qt.AlignVCenter
            }
        }

    }

    // MouseArea for hover and click handling
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.isDisabled ? Qt.ForbiddenCursor : Qt.PointingHandCursor
        enabled: !root.isDisabled

        onClicked: {
            console.log("MouseArea onClicked for delegateIndex:", root.delegateIndex)
            if (root.parentListView && !root.isDisabled) {
                if (root.parentListView.currentSelectionIsFromMouse !== undefined) {
                    root.parentListView.currentSelectionIsFromMouse = true
                }
                // Set currentIndex so the highlight follows
                root.parentListView.currentIndex = root.delegateIndex
                root.parentListView.itemSelected(root.delegateIndex, root)
            }
        }

        onDoubleClicked: {
            console.log("MouseArea onDoubleClicked for delegateIndex:", root.delegateIndex)
            if (root.parentListView && !root.isDisabled) {
                root.parentListView.itemDoubleClicked(root.delegateIndex, root)
            }
        }
    }
}
