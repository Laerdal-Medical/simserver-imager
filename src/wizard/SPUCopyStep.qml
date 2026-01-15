/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2024 Laerdal Medical AS
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import RpiImager

WizardStepBase {
    id: root
    objectName: "spuCopyStep"

    required property ImageWriter imageWriter
    required property var wizardContainer

    title: qsTr("Copy SPU to USB")
    subtitle: {
        if (root.isCopying) {
            return qsTr("Copying in progress — do not disconnect the USB drive")
        } else if (root.isComplete) {
            return qsTr("Copy complete — USB drive is ready")
        } else if (root.hasError) {
            return qsTr("An error occurred during copy")
        } else {
            return qsTr("Review and copy the SPU file to USB drive")
        }
    }

    nextButtonText: {
        if (root.isCopying) {
            return qsTr("Cancel")
        } else if (root.isComplete) {
            return CommonStrings.continueText
        } else {
            return qsTr("Copy to USB")
        }
    }

    nextButtonEnabled: !root.hasError
    showBackButton: true
    backButtonEnabled: !root.isCopying

    // State properties
    property bool isCopying: false
    property bool isComplete: false
    property bool hasError: false
    property string errorMessage: ""
    property string statusMessage: ""
    property real copyProgress: 0
    property int bytesNow: 0
    property int bytesTotal: 0

    // Format confirmation dialog state
    property bool showFormatDialog: false
    property bool driveHasCompatibleFs: false  // FAT32, exFAT, or NTFS

    // Connect to ImageWriter SPU signals
    Connections {
        target: root.imageWriter
        enabled: root.imageWriter !== null

        function onSpuCopyProgress(now, total) {
            root.bytesNow = now
            root.bytesTotal = total
            if (total > 0) {
                root.copyProgress = now / total
            }
        }

        function onSpuCopySuccess() {
            console.log("SPUCopyStep: Copy completed successfully")
            root.isCopying = false
            root.isComplete = true
            root.hasError = false
            root.statusMessage = qsTr("SPU file copied successfully!")
            // Auto-advance to done step
            root.nextClicked()
        }

        function onSpuCopyError(msg) {
            console.log("SPUCopyStep: Copy error:", msg)
            root.isCopying = false
            root.isComplete = false
            root.hasError = true
            root.errorMessage = msg
        }

        function onSpuPreparationStatusUpdate(msg) {
            console.log("SPUCopyStep: Status update:", msg)
            root.statusMessage = msg
        }
    }

    onNextClicked: {
        if (root.isCopying) {
            // Cancel
            root.imageWriter.cancelSpuCopy()
        } else if (root.isComplete) {
            // Continue to done step - handled by WizardContainer
        } else {
            // Start copy - check if drive has a compatible filesystem (FAT32, exFAT, or NTFS)
            root.driveHasCompatibleFs = root.imageWriter.isDriveCompatibleFilesystem()
            if (root.driveHasCompatibleFs) {
                // Already has compatible filesystem - copy directly (existing SPU files will be deleted)
                startCopy(true) // skipFormat = true
            } else {
                // Not a compatible filesystem - ask for confirmation before formatting
                root.showFormatDialog = true
            }
        }
    }

    function startCopy(skipFormat) {
        console.log("SPUCopyStep: Starting copy, skipFormat:", skipFormat)
        root.showFormatDialog = false
        root.isCopying = true
        root.isComplete = false
        root.hasError = false
        root.errorMessage = ""
        root.copyProgress = 0
        root.bytesNow = 0
        root.bytesTotal = 0
        root.statusMessage = qsTr("Preparing...")

        root.imageWriter.startSpuCopy(skipFormat)
    }

    function resetState() {
        root.isCopying = false
        root.isComplete = false
        root.hasError = false
        root.errorMessage = ""
        root.statusMessage = ""
        root.copyProgress = 0
        root.bytesNow = 0
        root.bytesTotal = 0
        root.showFormatDialog = false
    }

    Component.onCompleted: {
        resetState()
    }

    content: [
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.cardPadding
            spacing: Style.spacingLarge

            // Top spacer
            Item { Layout.fillHeight: true }

            // Main content area
            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: Style.sectionMaxWidth
                Layout.alignment: Qt.AlignHCenter
                spacing: Style.spacingLarge

                // Summary section (before copy starts)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingMedium
                    visible: !root.isCopying && !root.isComplete && !root.hasError && !root.showFormatDialog

                    Text {
                        text: qsTr("Summary")
                        font.pixelSize: Style.fontSizeHeading
                        font.family: Style.fontFamilyBold
                        font.bold: true
                        color: Style.formLabelColor
                        Layout.fillWidth: true
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Style.formColumnSpacing
                        rowSpacing: Style.spacingSmall

                        Text {
                            text: qsTr("SPU File:")
                            font.pixelSize: Style.fontSizeDescription
                            font.family: Style.fontFamily
                            color: Style.formLabelColor
                        }

                        Text {
                            text: wizardContainer.selectedSpuName || qsTr("None selected")
                            font.pixelSize: Style.fontSizeDescription
                            font.family: Style.fontFamilyBold
                            font.bold: true
                            color: Style.formLabelColor
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }

                        Text {
                            text: qsTr("USB Drive:")
                            font.pixelSize: Style.fontSizeDescription
                            font.family: Style.fontFamily
                            color: Style.formLabelColor
                        }

                        Text {
                            text: wizardContainer.selectedStorageName || qsTr("None selected")
                            font.pixelSize: Style.fontSizeDescription
                            font.family: Style.fontFamilyBold
                            font.bold: true
                            color: Style.formLabelColor
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }
                    }

                    // Info text
                    Text {
                        text: qsTr("If the USB drive is already FAT32, existing SPU files will be removed before copying.")
                        font.pixelSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        color: Style.textDescriptionColor
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                // Format confirmation dialog (when drive is not FAT32)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingMedium
                    visible: root.showFormatDialog

                    Rectangle {
                        Layout.fillWidth: true
                        height: formatDialogContent.implicitHeight + Style.spacingLarge * 2
                        color: Style.warningBackgroundColor
                        radius: Style.radiusMedium
                        border.color: Style.warningTextColor
                        border.width: 2

                        ColumnLayout {
                            id: formatDialogContent
                            anchors.fill: parent
                            anchors.margins: Style.spacingLarge
                            spacing: Style.spacingMedium

                            RowLayout {
                                spacing: Style.spacingSmall

                                Text {
                                    text: "\u26A0"
                                    font.pixelSize: Style.fontSizeHeading
                                    color: Style.warningTextColor
                                }

                                Text {
                                    text: qsTr("Format Required")
                                    font.pixelSize: Style.fontSizeHeading
                                    font.family: Style.fontFamilyBold
                                    font.bold: true
                                    color: Style.warningTextColor
                                }
                            }

                            Text {
                                text: qsTr("The USB drive is not FAT32 formatted. It must be formatted before copying the SPU file. All data on the drive will be erased.")
                                font.pixelSize: Style.fontSizeDescription
                                font.family: Style.fontFamily
                                color: Style.formLabelColor
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Style.spacingSmall
                                spacing: Style.spacingMedium

                                ImButton {
                                    text: qsTr("Cancel")
                                    Layout.fillWidth: true
                                    onClicked: root.showFormatDialog = false

                                    Accessible.name: qsTr("Cancel")
                                    Accessible.description: qsTr("Cancel and return to summary")
                                }

                                ImButtonRed {
                                    text: qsTr("Format and Copy")
                                    Layout.fillWidth: true
                                    onClicked: root.startCopy(false) // skipFormat = false

                                    Accessible.name: qsTr("Format and copy")
                                    Accessible.description: qsTr("Format the drive and copy the SPU file")
                                }
                            }
                        }
                    }
                }

                // Progress section (during copy)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingMedium
                    visible: root.isCopying

                    Text {
                        text: root.statusMessage
                        font.pixelSize: Style.fontSizeHeading
                        font.family: Style.fontFamilyBold
                        font.bold: true
                        color: Style.formLabelColor
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ProgressBar {
                        id: progressBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        from: 0
                        to: 1
                        value: root.copyProgress
                    }

                    Text {
                        text: {
                            if (root.bytesTotal > 0) {
                                return qsTr("%1 of %2")
                                    .arg(root.imageWriter.formatSize(root.bytesNow))
                                    .arg(root.imageWriter.formatSize(root.bytesTotal))
                            }
                            return ""
                        }
                        font.pixelSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        color: Style.textDescriptionColor
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.bytesTotal > 0
                    }
                }

                // Success section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingMedium
                    visible: root.isComplete

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
                        text: qsTr("Copy Complete!")
                        font.pixelSize: Style.fontSizeHeading
                        font.family: Style.fontFamilyBold
                        font.bold: true
                        color: Style.formLabelColor
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        text: qsTr("The SPU file has been copied to the USB drive. You can now safely remove it.")
                        font.pixelSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        color: Style.textDescriptionColor
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Error section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingMedium
                    visible: root.hasError

                    Rectangle {
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 80
                        Layout.alignment: Qt.AlignHCenter
                        radius: 40
                        color: Style.errorColor

                        Text {
                            anchors.centerIn: parent
                            text: "\u2717"
                            font.pixelSize: 40
                            color: "white"
                        }
                    }

                    Text {
                        text: qsTr("Copy Failed")
                        font.pixelSize: Style.fontSizeHeading
                        font.family: Style.fontFamilyBold
                        font.bold: true
                        color: Style.errorColor
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        text: root.errorMessage
                        font.pixelSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        color: Style.textDescriptionColor
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // Bottom spacer
            Item { Layout.fillHeight: true }
        }
    ]
}
