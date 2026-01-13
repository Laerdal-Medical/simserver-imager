/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import RpiImager

WizardStepBase {
    id: root

    required property ImageWriter imageWriter
    required property var wizardContainer

    readonly property HWListModel hwModel: imageWriter.getHWList()

    title: qsTr("Select your device")
    showNextButton: true
    // Enable Next when device selected OR when offline (so users can proceed with custom image)
    nextButtonEnabled: hasDeviceSelected || (osListUnavailable && hwlist.count === 0)

    property alias hwlist: hwlist
    property bool modelLoaded: false
    property bool hasDeviceSelected: false
    property bool isReloadingModel: false

    // Forward the nextClicked signal as next() function for keyboard auto-advance
    function next() {
        root.nextClicked()
    }

    Component.onCompleted: {
        // Initial load only
        if (!modelLoaded) onOsListPreparedHandler()
        
        // Register the ListView for keyboard navigation
        root.registerFocusGroup("device_list", function(){
            return [hwlist]
        }, 0)
        
        // Initial focus will automatically go to title, then first control (handled by WizardStepBase)
    }

    Connections {
        target: imageWriter
        function onOsListPrepared() {
            // If model was loaded but has no items (we were offline), force reload
            if (root.modelLoaded && root.hwModel && root.hwModel.rowCount() === 0) {
                root.modelLoaded = false
            }
            onOsListPreparedHandler()
        }
        function onOsListUnavailableChanged() {
            // When transitioning from unavailable to available, force a full reload
            if (!root.osListUnavailable && root.hwModel) {
                root.modelLoaded = false
                onOsListPreparedHandler()
            }
        }
    }
    
    // Called when OS list data is ready from network
    function onOsListPreparedHandler() {
        if (!root || !root.hwModel) {
            return
        }

        // Only reload if we haven't loaded yet, to avoid resetting scroll position during device selection
        if (!modelLoaded) {
            isReloadingModel = true
            var success = root.hwModel.reload()
            if (success) {
                modelLoaded = true
                // Do not auto-select first item to avoid unwanted highlighting on load
            }
            isReloadingModel = false
        }
    }
    
    // Track whether OS list is unavailable (no data loaded)
    readonly property bool osListUnavailable: imageWriter.isOsListUnavailable
    
    // Content
    content: [
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Offline/fetch failed placeholder (shown when list is empty due to network failure)
        Item {
            id: offlinePlaceholder
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: hwlist.count === 0 && root.osListUnavailable
            
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width * 0.8
                spacing: Style.spacingLarge
                
                // Icon or visual indicator
                Text {
                    text: "⚠"
                    font.pixelSize: 48
                    color: Style.textDescriptionColor
                    Layout.alignment: Qt.AlignHCenter
                    Accessible.ignored: true
                }
                
                Text {
                    text: qsTr("Unable to load device list")
                    font.pixelSize: Style.fontSizeHeading
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                    Accessible.ignored: false
                }
                
                Text {
                    text: qsTr("The device list could not be downloaded. Please check your internet connection and try again.\n\nYou can still write a local image file by pressing Next and selecting 'Use custom' on the following screen.")
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.textDescriptionColor
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                    Accessible.ignored: false
                }
                
                ImButton {
                    id: retryButton
                    text: qsTr("Retry")
                    Layout.alignment: Qt.AlignHCenter
                    accessibleDescription: qsTr("Retry downloading the device list")
                    onClicked: {
                        imageWriter.beginOSListFetch()
                    }
                }
            }
        }

        // Device list (fills available space, hidden when showing offline placeholder)
        SelectionListView {
            id: hwlist
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !offlinePlaceholder.visible
            model: root.hwModel
            delegate: hwdelegate
            keyboardAutoAdvance: true
            nextFunction: root.next
            accessibleName: {
                var count = hwlist.count
                var name = qsTr("Device selection list")
                
                if (count === 0) {
                    name += ". " + qsTr("No devices")
                } else if (count === 1) {
                    name += ". " + qsTr("1 device")
                } else {
                    name += ". " + qsTr("%1 devices").arg(count)
                }
                
                name += ". " + qsTr("Use arrow keys to navigate, Enter or Space to select")
                return name
            }
            accessibleDescription: ""
            
            Component.onCompleted: {
                if (root.hwModel && root.hwModel.currentIndex !== undefined && root.hwModel.currentIndex >= 0) {
                    currentIndex = root.hwModel.currentIndex
                    root.hasDeviceSelected = true
                }
                // Do not auto-select first item to avoid unwanted highlighting on load
            }
            
            onCurrentIndexChanged: {
                root.hasDeviceSelected = currentIndex !== -1
            }
            
            onItemSelected: function(index, item) {
                if (index >= 0 && index < model.rowCount()) {
                    // Only save/restore scroll position if we're not reloading the model
                    // (During model reload, the list may have changed and we should start at top)
                    var shouldPreserveScroll = !root.isReloadingModel
                    var savedContentY = shouldPreserveScroll ? contentY : 0

                    // Update ListView's currentIndex (for visual highlight)
                    currentIndex = index

                    // Set the model's current index (this triggers the HWListModel logic)
                    root.hwModel.currentIndex = index
                    // Use the model's currentName property
                    root.wizardContainer.selectedDeviceName = root.hwModel.currentName
                    root.hasDeviceSelected = true
                    
                    // Restore scroll position after all changes (clamped to valid range)
                    if (shouldPreserveScroll) {
                        Qt.callLater(function() {
                            // Clamp to valid range: 0 to (contentHeight - height)
                            var maxContentY = Math.max(0, contentHeight - height)
                            contentY = Math.min(Math.max(0, savedContentY), maxContentY)
                        })
                    }
                }
            }
            
            onItemDoubleClicked: function(index, item) {
                // First select the item
                if (index >= 0 && index < model.rowCount()) {
                    currentIndex = index
                    root.hwModel.currentIndex = index
                    root.wizardContainer.selectedDeviceName = root.hwModel.currentName
                    root.hasDeviceSelected = true
                    
                    // Then advance to next step (same as pressing Return)
                    Qt.callLater(function() {
                        if (root.nextButtonEnabled) {
                            root.next()
                        }
                    })
                }
            }
        }
    }
    ]
    
    // Device delegate component
    Component {
        id: hwdelegate

        SelectionListDelegate {
            id: hwDelegateItem

            required property int index
            required property string name
            required property string description
            required property string icon

            delegateIndex: hwDelegateItem.index
            itemTitle: hwDelegateItem.name
            itemDescription: hwDelegateItem.description
            itemIcon: hwDelegateItem.icon
        }
    }
} 
