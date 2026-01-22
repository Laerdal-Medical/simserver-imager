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

    // Cached style properties for use in nested components
    readonly property int styleScrollBarWidth: Style.scrollBarWidth
    readonly property color styleListViewHighlightColor: Style.listViewHighlightColor
    readonly property color styleListViewHoverRowBackgroundColor: Style.listViewHoverRowBackgroundColor
    readonly property color styleListViewRowBackgroundColor: Style.listViewRowBackgroundColor
    readonly property int styleSectionBorderRadius: Style.sectionBorderRadius
    readonly property int styleListItemPadding: Style.listItemPadding
    readonly property int styleSpacingSmall: Style.spacingSmall
    readonly property int styleSpacingMedium: Style.spacingMedium
    readonly property int styleSpacingXXSmall: Style.spacingXXSmall
    readonly property color styleTitleSeparatorColor: Style.titleSeparatorColor
    readonly property int styleFontSizeFormLabel: Style.fontSizeFormLabel
    readonly property string styleFontFamilyBold: Style.fontFamilyBold
    readonly property string styleFontFamily: Style.fontFamily
    readonly property color styleFormLabelDisabledColor: Style.formLabelDisabledColor
    readonly property color styleFormLabelColor: Style.formLabelColor
    readonly property int styleFontSizeDescription: Style.fontSizeDescription
    readonly property color styleTextDescriptionColor: Style.textDescriptionColor
    readonly property int styleFontSizeCaption: Style.fontSizeCaption
    readonly property color styleTextMetadataColor: Style.textMetadataColor
    readonly property int styleFontSizeSmall: Style.fontSizeSmall
    readonly property color styleFormLabelErrorColor: Style.formLabelErrorColor
    readonly property int styleFontSizeHeading: Style.fontSizeHeading

    // Sizing
    width: root.parentListView ? root.parentListView.width : 200
    height: root.isHidden ? 0 : Math.max(root.minimumHeight, contentRow.implicitHeight + root.styleSpacingSmall + root.styleSpacingMedium)
    visible: !root.isHidden

    // Accessibility
    Accessible.role: Accessible.ListItem
    Accessible.name: itemTitle + (itemDescription ? ". " + itemDescription : "") + (itemMetadata ? ". " + itemMetadata : "") + (isDisabled && disabledReason ? ". " + disabledReason : "")
    Accessible.focusable: true
    Accessible.ignored: false

    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        anchors.rightMargin: (root.parentListView && root.parentListView.contentHeight > root.parentListView.height) ? root.styleScrollBarWidth : 0

        color: root.isItemSelected ? root.selectedBackgroundColor
             : (root.parentListView && root.parentListView.currentIndex === root.delegateIndex) ? root.styleListViewHighlightColor
             : (mouseArea.containsMouse && !root.isDisabled ? root.styleListViewHoverRowBackgroundColor : root.styleListViewRowBackgroundColor)
        radius: root.styleSectionBorderRadius
        opacity: root.isDisabled ? 0.5 : 1.0
        Accessible.ignored: true

        RowLayout {
            id: contentRow
            anchors.fill: parent
            anchors.leftMargin: root.styleListItemPadding
            anchors.rightMargin: root.styleListItemPadding
            anchors.topMargin: root.styleSpacingSmall
            anchors.bottomMargin: root.styleSpacingMedium
            spacing: root.styleSpacingMedium

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
                    border.color: root.styleTitleSeparatorColor
                    border.width: 1
                    radius: 0
                    visible: imageIcon.status === Image.Error
                }
            }

            // Text content
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.styleSpacingXXSmall

                // Title row with badges
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.styleSpacingSmall

                    Text {
                        id: titleText
                        text: root.itemTitle
                        font.pixelSize: root.styleFontSizeFormLabel
                        font.family: root.styleFontFamilyBold
                        font.bold: true
                        color: root.isDisabled ? root.styleFormLabelDisabledColor
                             : root.isItemSelected ? root.selectedTextColor
                             : root.styleFormLabelColor
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
                    font.pixelSize: root.styleFontSizeDescription
                    font.family: root.styleFontFamily
                    color: root.isDisabled ? root.styleFormLabelDisabledColor
                         : root.isItemSelected ? root.selectedTextColor
                         : root.styleTextDescriptionColor
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: root.itemDescription !== ""
                    Accessible.ignored: true
                }

                // Primary metadata line
                Text {
                    text: root.itemMetadata
                    font.pixelSize: root.styleFontSizeCaption
                    font.family: root.styleFontFamily
                    color: root.isDisabled ? root.styleFormLabelDisabledColor
                         : root.isItemSelected ? root.selectedTextColor
                         : root.styleTextMetadataColor
                    Layout.fillWidth: true
                    visible: root.itemMetadata !== ""
                    Accessible.ignored: true
                }

                // Secondary metadata line
                Text {
                    text: root.itemMetadata2
                    font.pixelSize: root.styleFontSizeSmall
                    font.family: root.styleFontFamily
                    color: root.isDisabled ? root.styleFormLabelDisabledColor
                         : root.isItemSelected ? root.selectedTextColor
                         : root.styleTextMetadataColor
                    Layout.fillWidth: true
                    visible: root.itemMetadata2 !== ""
                    Accessible.ignored: true
                }
            }

            // Disabled reason indicator (e.g., "Read-only")
            Text {
                text: root.disabledReason
                font.pixelSize: root.styleFontSizeDescription
                font.family: root.styleFontFamily
                color: root.styleFormLabelErrorColor
                visible: root.isDisabled && root.disabledReason !== ""
                Layout.alignment: Qt.AlignVCenter
                Accessible.ignored: true
            }

            // Arrow indicator for sublists
            Text {
                text: "›"
                font.pixelSize: root.styleFontSizeHeading
                font.family: root.styleFontFamily
                color: root.isItemSelected ? root.selectedTextColor : root.styleTextDescriptionColor
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
