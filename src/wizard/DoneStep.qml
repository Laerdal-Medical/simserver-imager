/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import RpiImager

WizardStepBase {
    id: root
    
    required property ImageWriter imageWriter
    required property var wizardContainer

    // Detect if we completed an SPU copy operation
    readonly property bool isSpuCopyMode: wizardContainer.isSpuCopyMode

    title: isSpuCopyMode ? qsTr("Copy complete!") : qsTr("Write complete!")
    showBackButton: false
    showNextButton: false
    readonly property bool autoEjectEnabled: imageWriter.getBoolSetting("eject")
    // Use snapshot of customization flags captured when write completed
    // This preserves the state even after token/flags are cleared for security
    readonly property bool anyCustomizationsApplied: (
        wizardContainer.completionSnapshot.customizationSupported && (
            wizardContainer.completionSnapshot.hostnameConfigured ||
            wizardContainer.completionSnapshot.localeConfigured ||
            wizardContainer.completionSnapshot.userConfigured ||
            wizardContainer.completionSnapshot.wifiConfigured ||
            wizardContainer.completionSnapshot.sshEnabled ||
            wizardContainer.completionSnapshot.piConnectEnabled ||
            wizardContainer.completionSnapshot.ifI2cEnabled ||
            wizardContainer.completionSnapshot.ifSpiEnabled ||
            wizardContainer.completionSnapshot.if1WireEnabled ||
            wizardContainer.completionSnapshot.ifSerial !== ""  && wizardContainer.completionSnapshot.ifSerial !== "Disabled" ||
            wizardContainer.completionSnapshot.featUsbGadgetEnabled
        )
    )

    // Check if we have write statistics to display
    readonly property bool hasWriteStats: (
        wizardContainer.completionSnapshot.writeBytesTotal > 0 &&
        wizardContainer.completionSnapshot.writeDurationSecs > 0
    )

    // Helper functions for formatting statistics
    function formatDuration(seconds) {
        if (seconds < 60) {
            return qsTr("%1 sec").arg(Math.round(seconds))
        } else {
            var mins = Math.floor(seconds / 60)
            var secs = Math.round(seconds % 60)
            if (secs === 0) {
                return qsTr("%1 min").arg(mins)
            }
            return qsTr("%1 min %2 sec").arg(mins).arg(secs)
        }
    }

    function formatBytes(bytes) {
        if (bytes < 1024 * 1024) {
            return qsTr("%1 KB").arg((bytes / 1024).toFixed(1))
        } else if (bytes < 1024 * 1024 * 1024) {
            return qsTr("%1 MB").arg((bytes / (1024 * 1024)).toFixed(1))
        } else {
            return qsTr("%1 GB").arg((bytes / (1024 * 1024 * 1024)).toFixed(2))
        }
    }

    function calculateAverageSpeed(bytes, seconds) {
        if (seconds <= 0) return ""
        var mbps = bytes / (1024 * 1024) / seconds
        return qsTr("%1 MB/s").arg(mbps.toFixed(1))
    }

    // Content
    content: [
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.cardPadding
        spacing: Style.spacingLarge
        
        // SPU copy completion message (simple view)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacingLarge
            visible: root.isSpuCopyMode

            Rectangle {
                Layout.preferredWidth: 80
                Layout.preferredHeight: 80
                Layout.alignment: Qt.AlignHCenter
                radius: 40
                color: Style.successColor

                Text {
                    anchors.centerIn: parent
                    text: "\u2713"
                    font.pixelSize: 40
                    color: "white"
                }
            }

            Text {
                text: qsTr("SPU file copied successfully!")
                font.pixelSize: Style.fontSizeHeading
                font.family: Style.fontFamilyBold
                font.bold: true
                color: Style.formLabelColor
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                text: root.wizardContainer.selectedSpuName || ""
                font.pixelSize: Style.fontSizeDescription
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: text.length > 0
            }

            Text {
                text: qsTr("Copied to: %1").arg(root.wizardContainer.selectedStorageName || "")
                font.pixelSize: Style.fontSizeDescription
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: root.wizardContainer.selectedStorageName
            }

            Text {
                text: root.autoEjectEnabled
                    ? qsTr("The USB drive was ejected automatically. You can now remove it safely.")
                    : qsTr("Please eject the USB drive before removing it from your computer.")
                font.pixelSize: Style.fontSizeDescription
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.topMargin: Style.spacingMedium
            }
        }

        // What was configured (de-chromed) - hidden for SPU copy mode
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacingMedium
            visible: !root.isSpuCopyMode

            Text {
                id: choicesHeading
                text: qsTr("Your choices:")
                font.pixelSize: Style.fontSizeHeading
                font.family: Style.fontFamilyBold
                font.bold: true
                color: Style.formLabelColor
                Layout.fillWidth: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
                Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
            }
            
            GridLayout {
                id: choicesGrid
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Style.formColumnSpacing
                rowSpacing: Style.spacingSmall
                
                Text {
                    id: deviceLabel
                    text: CommonStrings.device
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text + ": " + (wizardContainer.selectedDeviceName || CommonStrings.noDeviceSelected)
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }
                Text {
                    id: deviceValue
                    text: wizardContainer.selectedDeviceName || CommonStrings.noDeviceSelected
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    Accessible.ignored: true

                    ToolTip.text: text
                    ToolTip.visible: truncated && deviceValueMouseArea.containsMouse
                    ToolTip.delay: 500
                    MouseArea {
                        id: deviceValueMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
                
                Text {
                    id: osLabel
                    text: qsTr("Operating system:")
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text + " " + (wizardContainer.selectedOsName || CommonStrings.noImageSelected)
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }
                Text {
                    id: osValue
                    text: wizardContainer.selectedOsName || CommonStrings.noImageSelected
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    Accessible.ignored: true

                    ToolTip.text: text
                    ToolTip.visible: truncated && osValueMouseArea.containsMouse
                    ToolTip.delay: 500
                    MouseArea {
                        id: osValueMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
                
                Text {
                    id: storageLabel
                    text: qsTr("Storage:")
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text + " " + (wizardContainer.selectedStorageName || CommonStrings.noStorageSelected)
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }
                Text {
                    id: storageValue
                    text: wizardContainer.selectedStorageName || CommonStrings.noStorageSelected
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    Accessible.ignored: true

                    ToolTip.text: text
                    ToolTip.visible: truncated && storageValueMouseArea.containsMouse
                    ToolTip.delay: 500
                    MouseArea {
                        id: storageValueMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }
            
            // Customization summary
            Text {
                id: customizationsHeading
                text: qsTr("Customisations applied:")
                font.pixelSize: Style.fontSizeFormLabel
                font.family: Style.fontFamilyBold
                font.bold: true
                color: Style.formLabelColor
                Layout.fillWidth: true
                Layout.topMargin: Style.spacingSmall
                visible: root.anyCustomizationsApplied
                Accessible.role: Accessible.Heading
                Accessible.name: text
                Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
            }
            
            ScrollView {
                id: customizationScrollView
                Layout.fillWidth: true
                Layout.maximumHeight: Math.round(root.height * 0.4)
                clip: true
                visible: root.anyCustomizationsApplied
                activeFocusOnTab: true
                Accessible.role: Accessible.List
                Accessible.name: {
                    // Build a list of visible customizations to announce using snapshot
                    var items = []
                    var snapshot = wizardContainer.completionSnapshot
                    if (snapshot.hostnameConfigured) items.push(CommonStrings.hostnameConfigured)
                    if (snapshot.localeConfigured) items.push(CommonStrings.localeConfigured)
                    if (snapshot.userConfigured) items.push(CommonStrings.userAccountConfigured)
                    if (snapshot.wifiConfigured) items.push(CommonStrings.wifiConfigured)
                    if (snapshot.sshEnabled) items.push(CommonStrings.sshEnabled)
                    if (snapshot.piConnectEnabled) items.push(CommonStrings.piConnectEnabled)
                    if (snapshot.featUsbGadgetEnabled) items.push(CommonStrings.usbGadgetEnabled)
                    if (snapshot.ifI2cEnabled) items.push(CommonStrings.i2cEnabled)
                    if (snapshot.ifSpiEnabled) items.push(CommonStrings.spiEnabled)
                    if (snapshot.if1WireEnabled) items.push(CommonStrings.onewireEnabled)
                    if (snapshot.ifSerial !== "" && snapshot.ifSerial !== "Disabled") items.push(CommonStrings.serialConfigured)
                    
                    return items.length + " " + (items.length === 1 ? qsTr("customization") : qsTr("customizations")) + ": " + items.join(", ")
                }
                Flickable {
                    contentWidth: parent.width
                    contentHeight: customizationColumn.height
                    
                    Keys.onUpPressed: {
                        if (contentY > 0) {
                            contentY = Math.max(0, contentY - 20)
                        }
                    }
                    Keys.onDownPressed: {
                        var maxY = Math.max(0, contentHeight - height)
                        if (contentY < maxY) {
                            contentY = Math.min(maxY, contentY + 20)
                        }
                    }
                    
                    Column {
                        id: customizationColumn
                        width: parent.width
                        property var snapshot: wizardContainer.completionSnapshot
                        Text { text: "✓ " + CommonStrings.hostnameConfigured; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.hostnameConfigured }
                        Text { text: "✓ " + CommonStrings.localeConfigured; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.localeConfigured }
                        Text { text: "✓ " + CommonStrings.userAccountConfigured; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.userConfigured }
                        Text { text: "✓ " + CommonStrings.wifiConfigured; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.wifiConfigured }
                        Text { text: "✓ " + CommonStrings.sshEnabled; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.sshEnabled }
                        Text { text: "✓ " + CommonStrings.piConnectEnabled; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.piConnectEnabled }
                        Text { text: "✓ " + CommonStrings.usbGadgetEnabled; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.featUsbGadgetEnabled }
                        Text { text: "✓ " + CommonStrings.i2cEnabled; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.ifI2cEnabled }
                        Text { text: "✓ " + CommonStrings.spiEnabled; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.ifSpiEnabled }
                        Text { text: "✓ " + CommonStrings.onewireEnabled; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.if1WireEnabled }
                        Text { text: "✓ " + CommonStrings.serialConfigured; font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor; visible: customizationColumn.snapshot.ifSerial !== "" && customizationColumn.snapshot.ifSerial !== "Disabled" }
                    }
                }
                ScrollBar.vertical: ScrollBar { policy: contentItem.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff; width: Style.scrollBarWidth }
            }

            // Write statistics section
            Text {
                id: statsHeading
                text: qsTr("Write statistics:")
                font.pixelSize: Style.fontSizeFormLabel
                font.family: Style.fontFamilyBold
                font.bold: true
                color: Style.formLabelColor
                Layout.fillWidth: true
                Layout.topMargin: Style.spacingSmall
                visible: root.hasWriteStats
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            GridLayout {
                id: statsGrid
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Style.formColumnSpacing
                rowSpacing: Style.spacingSmall
                visible: root.hasWriteStats

                // Write row
                Text {
                    text: qsTr("Write:")
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    visible: wizardContainer.completionSnapshot.writeBytesTotal > 0 && wizardContainer.completionSnapshot.writeDurationSecs > 0
                }
                Text {
                    text: qsTr("%1 in %2 (%3)")
                        .arg(root.formatBytes(wizardContainer.completionSnapshot.writeBytesTotal))
                        .arg(root.formatDuration(wizardContainer.completionSnapshot.writeDurationSecs))
                        .arg(root.calculateAverageSpeed(wizardContainer.completionSnapshot.writeBytesTotal, wizardContainer.completionSnapshot.writeDurationSecs))
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    visible: wizardContainer.completionSnapshot.writeBytesTotal > 0 && wizardContainer.completionSnapshot.writeDurationSecs > 0
                }

                // Verify row
                Text {
                    text: qsTr("Verify:")
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    visible: wizardContainer.completionSnapshot.verifyDurationSecs > 0
                }
                Text {
                    text: qsTr("%1 (%2)")
                        .arg(root.formatDuration(wizardContainer.completionSnapshot.verifyDurationSecs))
                        .arg(root.calculateAverageSpeed(wizardContainer.completionSnapshot.writeBytesTotal, wizardContainer.completionSnapshot.verifyDurationSecs))
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    visible: wizardContainer.completionSnapshot.verifyDurationSecs > 0
                }
            }

            Text {
                id: ejectInstruction
                text: root.autoEjectEnabled ? qsTr("The storage device was ejected automatically. You can now remove it safely.") : qsTr("Please eject the storage device before removing it from your computer.")
                font.pixelSize: Style.fontSizeDescription
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
                Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
            }
        }        
    }
    ]
    
    // Custom button container - network info is automatically added by WizardStepBase
    customButtonContainer: [
        Item {
            Layout.fillWidth: true
        },
        
        ImButton {
            id: writeAnotherButton
            text: qsTr("Write Another")
            accessibleDescription: qsTr("Return to storage selection to write the same image to another storage device")
            enabled: true
            activeFocusOnTab: true
            Layout.minimumWidth: Style.buttonWidthMinimum
            Layout.preferredHeight: Style.buttonHeightStandard
            onClicked: {
                // Return to storage selection to write the same image to another SD card
                // This preserves device, OS, and customization settings
                wizardContainer.resetToWriteStep()
            }
        },
        
        ImButtonRed {
            id: finishButton
            text: imageWriter.isEmbeddedMode() ? qsTr("Reboot") : CommonStrings.finish
            accessibleDescription: imageWriter.isEmbeddedMode() ? qsTr("Reboot the system to apply changes") : qsTr("Close Laerdal SimServer Imager and exit the application")
            enabled: true
            activeFocusOnTab: true
            Layout.minimumWidth: Style.buttonWidthMinimum
            Layout.preferredHeight: Style.buttonHeightStandard
            onClicked: {
                if (imageWriter.isEmbeddedMode()) {
                    imageWriter.reboot()
                } else {
                    // Close the application
                    // Advanced options settings are already saved
                    Qt.quit()
                }
            }
        }
    ]
    
    // Focus management - rebuild when customization visibility changes
    onAnyCustomizationsAppliedChanged: rebuildFocusOrder()
    
    Component.onCompleted: {
        // Register choices section as first focus group
        registerFocusGroup("choices", function() {
            return [choicesHeading, deviceLabel, osLabel, storageLabel]
        }, 0)
        
        // Register customizations section as second focus group
        registerFocusGroup("customizations", function() {
            var items = []
            if (customizationScrollView.visible) {
                items.push(customizationsHeading)
                items.push(customizationScrollView)
            }
            return items
        }, 1)
        
        // Register eject instruction as third focus group
        registerFocusGroup("eject", function() {
            return [ejectInstruction]
        }, 2)
        
        // Register custom buttons as fourth focus group
        registerFocusGroup("buttons", function() {
            return [writeAnotherButton, finishButton]
        }, 3)
        
        // Ensure focus order is built after custom buttons are fully instantiated
        Qt.callLater(function() {
            rebuildFocusOrder()
        })
    }

} 
