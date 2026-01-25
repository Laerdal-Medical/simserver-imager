/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

import RpiImager
import ImageOptions

WizardStepBase {
    id: root
    objectName: "writingStep"

    required property ImageWriter imageWriter
    required property var wizardContainer

    title: qsTr("Write image")
    subtitle: {
        if (root.isWriting) {
            return qsTr("Writing in progress — do not disconnect the storage device")
        } else if (root.isComplete) {
            return qsTr("Write complete")
        } else {
            return qsTr("Review your choices and write the image to the storage device")
        }
    }
    nextButtonText: {
        if (root.isWriting) {
            // Show specific cancel text based on write state
            if (root.imageWriter.writeState === ImageWriter.Verifying) {
                return qsTr("Skip verification")
            } else {
                return qsTr("Cancel write")
            }
        } else if (root.isComplete) {
            return CommonStrings.continueText
        } else {
            return qsTr("Write")
        }
    }
    nextButtonAccessibleDescription: {
        if (root.isWriting) {
            if (root.imageWriter.writeState === ImageWriter.Verifying) {
                return qsTr("Skip verification and finish the write process")
            } else {
                return qsTr("Cancel the write operation and return to the summary")
            }
        } else if (root.isComplete) {
            return qsTr("Continue to the completion screen")
        } else {
            return qsTr("Begin writing the image to the storage device. All existing data will be erased.")
        }
    }
    backButtonAccessibleDescription: qsTr("Return to previous customization step")
    nextButtonEnabled: root.isWriting || root.isComplete || root.imageWriter.readyToWrite()
    showBackButton: true

    property bool isWriting: false
    property bool isVerifying: false
    property bool cancelPending: false
    property bool isFinalising: false
    property bool isComplete: false
    property bool confirmOpen: false
    property string bottleneckStatus: ""
    property int writeThroughputKBps: 0

    // Progress tracking for speed and time estimation
    property real progressBytesNow: 0
    property real progressBytesTotal: 0

    // Verification speed tracking
    property real lastVerifyBytes: 0
    property real lastVerifyTime: 0
    property int verifyThroughputKBps: 0

    // Download speed tracking
    property real lastDownloadBytes: 0
    property real lastDownloadTime: 0
    property real downloadThroughputMbps: 0  // Megabits per second
    property real downloadBytesNow: 0
    property real downloadBytesTotal: 0

    // Write statistics for completion summary
    property real writeStartTime: 0
    property real writeBytesTotal: 0
    property real writeDurationSecs: 0
    property real verifyDurationSecs: 0
    property real writePhaseStartTime: 0
    property real verifyPhaseStartTime: 0
    readonly property bool anyCustomizationsApplied: (
        root.wizardContainer.customizationSupported && (
            root.wizardContainer.hostnameConfigured ||
            root.wizardContainer.localeConfigured ||
            root.wizardContainer.userConfigured ||
            root.wizardContainer.wifiConfigured ||
            root.wizardContainer.sshEnabled ||
            root.wizardContainer.piConnectEnabled ||
            root.wizardContainer.featUsbGadgetEnabled
        )
    )

    // Disable back while writing
    backButtonEnabled: !root.isWriting && !root.cancelPending && !root.isFinalising

    // Content
    content: [
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.cardPadding
        spacing: Style.spacingLarge

        // Top spacer to vertically center progress section when writing/complete
        Item { Layout.fillHeight: true; visible: root.isWriting || root.isComplete }

        // Summary section (de-chromed)
        ColumnLayout {
            id: summaryLayout
            Layout.fillWidth: true
            Layout.maximumWidth: Style.sectionMaxWidth
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.spacingMedium
            visible: !root.isWriting && !root.cancelPending && !root.isFinalising && !root.isComplete

            Text {
                id: summaryHeading
                text: qsTr("Summary")
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
                id: summaryGrid
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
                    Accessible.name: text + ": " + (root.wizardContainer.selectedDeviceName || CommonStrings.noDeviceSelected)
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }

                MarqueeText {
                    id: deviceValue
                    text: root.wizardContainer.selectedDeviceName || CommonStrings.noDeviceSelected
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    Accessible.ignored: true  // Read as part of the label
                }

                Text {
                    id: osLabel
                    text: qsTr("Operating system:")
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text + " " + (root.wizardContainer.selectedOsName || CommonStrings.noImageSelected)
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }

                MarqueeText {
                    id: osValue
                    text: root.wizardContainer.selectedOsName || CommonStrings.noImageSelected
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    Accessible.ignored: true  // Read as part of the label
                }

                Text {
                    id: storageLabel
                    text: CommonStrings.storage
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text + ": " + (root.wizardContainer.selectedStorageName || CommonStrings.noStorageSelected)
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }

                MarqueeText {
                    id: storageValue
                    text: root.wizardContainer.selectedStorageName || CommonStrings.noStorageSelected
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    Accessible.ignored: true  // Read as part of the label
                }
            }
        }

        // Customization summary (what will be written) - de-chromed
        ColumnLayout {
            id: customLayout
            Layout.fillWidth: true
            Layout.maximumWidth: Style.sectionMaxWidth
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.spacingMedium
            visible: !root.isWriting && !root.cancelPending && !root.isFinalising && !root.isComplete && root.anyCustomizationsApplied

            Text {
                id: customizationsHeading
                text: qsTr("Customisations to apply:")
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

            ScrollView {
                id: customizationsScrollView
                Layout.fillWidth: true
                // Cap height so long lists become scrollable in default window size
                Layout.maximumHeight: Math.round(root.height * 0.4)
                clip: true
                activeFocusOnTab: true
                Accessible.role: Accessible.List
                Accessible.name: {
                    // Build a list of visible customizations to announce
                    var items = []
                    if (root.wizardContainer.hostnameConfigured) items.push(CommonStrings.hostnameConfigured)
                    if (root.wizardContainer.localeConfigured) items.push(CommonStrings.localeConfigured)
                    if (root.wizardContainer.userConfigured) items.push(CommonStrings.userAccountConfigured)
                    if (root.wizardContainer.wifiConfigured) items.push(CommonStrings.wifiConfigured)
                    if (root.wizardContainer.sshEnabled) items.push(CommonStrings.sshEnabled)
                    if (root.wizardContainer.piConnectEnabled) items.push(CommonStrings.piConnectEnabled)
                    if (root.wizardContainer.featUsbGadgetEnabled) items.push(CommonStrings.usbGadgetEnabled)
                    if (root.wizardContainer.ifI2cEnabled) items.push(CommonStrings.i2cEnabled)
                    if (root.wizardContainer.ifSpiEnabled) items.push(CommonStrings.spiEnabled)
                    if (root.wizardContainer.if1WireEnabled) items.push(CommonStrings.onewireEnabled)
                    if (root.wizardContainer.ifSerial !== "" && root.wizardContainer.ifSerial !== "Disabled") items.push(CommonStrings.serialConfigured)

                    return items.length + " " + (items.length === 1 ? qsTr("customization") : qsTr("customizations")) + ": " + items.join(", ")
                }
                contentItem: Flickable {
                    id: customizationsFlickable
                    contentWidth: width
                    contentHeight: customizationsColumn.implicitHeight
                    interactive: contentHeight > height
                    clip: true
                    
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
                        id: customizationsColumn
                        width: parent.width
                        spacing: Style.spacingXSmall
                        Text { text: "• " + CommonStrings.hostnameConfigured;      font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.hostnameConfigured;         Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.localeConfigured;        font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.localeConfigured;           Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.userAccountConfigured;   font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.userConfigured;             Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.wifiConfigured;          font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.wifiConfigured;             Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.sshEnabled;              font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.sshEnabled;                 Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.piConnectEnabled;        font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.piConnectEnabled;           Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.usbGadgetEnabled;        font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.featUsbGadgetEnabled;       Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.i2cEnabled;              font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.ifI2cEnabled;               Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.spiEnabled;              font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.ifSpiEnabled;               Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.onewireEnabled;          font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.if1WireEnabled;             Accessible.role: Accessible.ListItem; Accessible.name: text }
                        Text { text: "• " + CommonStrings.serialConfigured;        font.pixelSize: Style.fontSizeDescription; font.family: Style.fontFamily; color: Style.formLabelColor;     visible: root.wizardContainer.ifSerial !== "" && root.wizardContainer.ifSerial !== "Disabled"; Accessible.role: Accessible.ListItem; Accessible.name: text }
                    }
                }
                ScrollBar.vertical: ImScrollBar {}
            }
        }

        // Progress section (de-chromed)
        ColumnLayout {
            id: progressLayout
            Layout.fillWidth: true
            Layout.maximumWidth: Style.sectionMaxWidth
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.spacingMedium
            visible: root.isWriting || root.cancelPending || root.isFinalising || root.isComplete

            ImProgressBar {
                id: progressBar
                Layout.fillWidth: true
                Layout.preferredHeight: Style.spacingLarge
                value: 0
                from: 0
                to: 100
                visible: (root.isWriting || root.isFinalising)
                fillColor: {
                    // Use green for verification, blue for writing
                    if (root.imageWriter.writeState === ImageWriter.Verifying) {
                        return Style.progressBarVerifyForegroundColor
                    }
                    return Style.progressBarWritingForegroundColor
                }
                showText: true
                indeterminate: ( root.imageWriter.writeState === ImageWriter.Preparing || root.imageWriter.writeState === ImageWriter.Idle )
                indeterminateText: qsTr("Starting write process...")
                onIndeterminateChanged: {
                    // Update accessible description when indeterminate state changes
                    console.log("Indeterminate changed to", indeterminate, "Write state:", root.imageWriter.writeState)
                }
                text: ""

                Accessible.role: Accessible.ProgressBar
                Accessible.name: qsTr("Write progress")
                Accessible.description: progressBar.text
            }
            
            // Speed and time remaining display
            Text {
                id: speedTimeText
                text: {
                    var parts = []

                    // Show download speed during preparation/download phase
                    if (root.imageWriter.writeState === ImageWriter.Preparing && root.downloadThroughputMbps > 0) {
                        parts.push(Math.round(root.downloadThroughputMbps) + " Mbps")
                        var downloadTimeRemaining = root.calculateDownloadTimeRemaining()
                        var downloadTimeStr = Utils.formatTimeRemaining(downloadTimeRemaining)
                        if (downloadTimeStr !== "") {
                            parts.push(downloadTimeStr)
                        }
                    }
                    // Show write/verify speed during write phase
                    else if (root.isWriting && !root.isFinalising) {
                        if (root.bottleneckStatus !== "") {
                            parts.push(root.bottleneckStatus)
                        }
                        if (root.progressBytesTotal > 0) {
                            parts.push(Utils.formatBytes(root.progressBytesNow) + " / " +
                                      Utils.formatBytes(root.progressBytesTotal))
                        }
                        // Show verification speed during verify, write speed otherwise
                        var throughput = root.isVerifying ? root.verifyThroughputKBps : root.writeThroughputKBps
                        if (throughput > 0) {
                            parts.push(Math.round(throughput / 1024) + " MB/s")
                        }
                        var timeRemaining = root.calculateTimeRemaining(throughput)
                        var timeStr = Utils.formatTimeRemaining(timeRemaining)
                        if (timeStr !== "") {
                            parts.push(timeStr)
                        }
                    }

                    return parts.join("  •  ")
                }
                font.pixelSize: Style.fontSizeDescription
                font.family: Style.fontFamily
                color: Style.formLabelColor
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }

        // Bottom spacer to vertically center progress section when writing/complete
        Item { Layout.fillHeight: true; visible: root.isWriting || root.isComplete }
    }
    ]


    // Calculate estimated time remaining based on current speed
    function calculateTimeRemaining(throughput): int {
        return Utils.calculateTimeRemainingKBps(
            root.progressBytesNow,
            root.progressBytesTotal,
            throughput
        )
    }

    function calculateDownloadTimeRemaining(): int {
        return Utils.calculateTimeRemainingMbps(
            root.downloadBytesNow,
            root.downloadBytesTotal,
            root.downloadThroughputMbps
        )
    }


    // Handle next button clicks based on current state
    onNextClicked: {
        if (root.isWriting) {
            // If we're in verification phase, skip verification and let write complete successfully
            if (root.imageWriter.writeState === ImageWriter.Verifying) {
                root.imageWriter.skipCurrentVerification()
            } else {
                // Cancel the actual write operation
                root.cancelPending = true
                root.isVerifying = false
                root.isFinalising = true
                progressBar.value = 100
                progressBar.text = qsTr("Finalizing…")
                root.imageWriter.cancelWrite()
            }
        } else if (!root.isComplete) {
            // If warnings are disabled, skip the confirmation dialog
            if (root.wizardContainer.disableWarnings) {
                beginWriteDelay.start()
            } else {
                // Open confirmation dialog before starting
                confirmDialog.open()
            }
        } else {
            // Writing is complete, advance to next step
            root.wizardContainer.nextStep()
        }
    }

    function onFinalizing() {
        root.isVerifying = false
        progressBar.text = qsTr("Finalizing...")
        progressBar.value = 100
    }

    // Confirmation dialog
    MessageDialog {
        id: confirmDialog
        imageWriter: root.imageWriter
        parent: root.Window.window ? root.Window.window.overlayRootItem : undefined
        anchors.centerIn: parent

        // Show warning icon in header
        headerIconVisible: true
        headerIconBackgroundColor: Style.warningTextColor
        headerIconText: "!"
        headerIconAccessibleName: qsTr("Warning icon")
        title: qsTr("You are about to ERASE all data on:\n%1").arg(root.wizardContainer.selectedStorageName || qsTr("the storage device"))
        titleColor: Style.formLabelErrorColor

        // Message content
        message: qsTr("This action is PERMANENT and CANNOT be undone.")

        // Primary button with countdown
        destructiveButton: true
        buttonText: confirmDialog.allowAccept ? qsTr("Erase and write") : qsTr("Wait... %1").arg(confirmDialog.countdown)
        buttonAccessibleDescription: confirmDialog.allowAccept
            ? qsTr("Confirm erasure and begin writing the image to the storage device")
            : qsTr("Please wait %1 seconds before confirming").arg(confirmDialog.countdown)

        property bool allowAccept: false
        property int countdown: 2

        // Custom escape handling
        function escapePressed() {
            confirmDialog.close()
        }

        // Disable action button until countdown completes
        Component.onCompleted: {
            actionButtonItem.enabled = Qt.binding(function() { return confirmDialog.allowAccept })
            actionButtonItem.activeFocusOnTab = Qt.binding(function() { return confirmDialog.allowAccept })

            registerFocusGroup("content", function(){
                if (confirmDialog.imageWriter && confirmDialog.imageWriter.isScreenReaderActive()) {
                    return [messageTextItem]
                }
                return []
            }, 0)
            registerFocusGroup("buttons", function(){
                return [cancelButton, actionButtonItem]
            }, 1)
        }

        onOpened: {
            allowAccept = false
            countdown = 2
            confirmDelay.start()
        }
        onClosed: {
            confirmDelay.stop()
            allowAccept = false
            countdown = 2
        }

        onAccepted: {
            beginWriteDelay.start()
        }

        // Cancel button
        footerButtons: [
            ImButton {
                id: cancelButton
                text: CommonStrings.cancel
                accessibleDescription: qsTr("Cancel and return to the write summary without erasing the storage device")
                onClicked: confirmDialog.close()
            }
        ]
    }

    // Delay accept for 2 seconds - moved outside dialog content
    Timer {
        id: confirmDelay
        interval: 1000
        running: false
        repeat: true
        onTriggered: {
            confirmDialog.countdown--
            if (confirmDialog.countdown <= 0) {
                confirmDelay.stop()
                confirmDialog.allowAccept = true
            }
        }
    }

    // Defer starting the write slightly until after the dialog has fully closed,
    // to avoid OS authentication prompts being cancelled by focus changes.
    Timer {
        id: beginWriteDelay
        interval: 300
        running: false
        repeat: false
        onTriggered: {
            // Ensure our window regains focus before elevating privileges
            root.forceActiveFocus()
            root.isWriting = true
            root.wizardContainer.isWriting = true
            root.bottleneckStatus = ""
            root.writeThroughputKBps = 0
            root.progressBytesNow = 0
            root.progressBytesTotal = 0
            // Reset download tracking
            root.downloadThroughputMbps = 0
            root.lastDownloadBytes = 0
            root.lastDownloadTime = 0
            root.downloadBytesNow = 0
            root.downloadBytesTotal = 0
            // Reset timing stats
            root.writeStartTime = Date.now()
            root.writeBytesTotal = 0
            root.writeDurationSecs = 0
            root.verifyDurationSecs = 0
            root.writePhaseStartTime = 0
            root.verifyPhaseStartTime = 0
            progressBar.text = qsTr("Starting write process...")
            progressBar.value = 0
            Qt.callLater(function(){ root.imageWriter.startWrite() })
        }
    }

    function onDownloadProgress(now, total) {
        // Show download progress during artifact download (preparation phase)
        if (root.isWriting && root.imageWriter.writeState === ImageWriter.Preparing) {
            var progress = total > 0 ? (now / total) * 100 : 0
            progressBar.value = progress
            progressBar.text = qsTr("Downloading... %1%").arg(Math.round(progress))

            // Store current download bytes for time remaining calculation
            root.downloadBytesNow = now
            root.downloadBytesTotal = total

            // Calculate download speed every 500ms using EMA smoothing
            var result = Utils.calculateThroughputMbps(
                now,
                root.lastDownloadBytes,
                root.lastDownloadTime,
                root.downloadThroughputMbps,
                500,  // Update every 500ms
                0.3   // EMA smoothing factor
            )

            if (result !== null) {
                root.downloadThroughputMbps = result.throughputMbps
                root.lastDownloadBytes = result.newLastBytes
                root.lastDownloadTime = result.newLastTime
            }
        }
    }

    function onWriteProgress(now, total) {
        if (root.isWriting) {
            // Track when write phase actually starts
            if (root.writePhaseStartTime === 0 && now > 0) {
                root.writePhaseStartTime = Date.now()
            }
            // Clear download throughput when write phase begins
            root.downloadThroughputMbps = 0
            root.progressBytesNow = now
            root.progressBytesTotal = total
            root.writeBytesTotal = total
            if (total > 0) {
                var progress = (now / total) * 100
                progressBar.indeterminate = false
                progressBar.value = progress
                progressBar.text = qsTr("Writing... %1%").arg(Math.round(progress))
            } else {
                // Unknown total (e.g. compressed file with no decompressed size metadata)
                progressBar.indeterminate = true
                progressBar.indeterminateText = qsTr("Writing... %1").arg(Utils.formatBytes(now))
            }
        }
    }

    function onVerifyProgress(now, total) {
        if (root.isWriting) {
            // When verification starts, record write phase duration
            if (!root.isVerifying) {
                root.isVerifying = true
                progressBar.indeterminate = false
                if (root.writePhaseStartTime > 0) {
                    root.writeDurationSecs = (Date.now() - root.writePhaseStartTime) / 1000
                }
                root.verifyPhaseStartTime = Date.now()
                root.lastVerifyBytes = 0
                root.lastVerifyTime = Date.now()
                root.verifyThroughputKBps = 0
            }

            // Calculate verification throughput
            var result = Utils.calculateThroughputKBps(
                now,
                root.lastVerifyBytes,
                root.lastVerifyTime,
                500  // Update every 500ms
            )

            if (result !== null) {
                root.verifyThroughputKBps = result.throughputKBps
                root.lastVerifyBytes = result.newLastBytes
                root.lastVerifyTime = result.newLastTime
            }

            root.progressBytesNow = now
            root.progressBytesTotal = total
            root.bottleneckStatus = ""  // Clear write bottleneck during verification
            var progress = total > 0 ? (now / total) * 100 : 0
            progressBar.value = progress
            progressBar.text = qsTr("Verifying... %1%").arg(Math.round(progress))
        }
    }

    function onPreparationStatusUpdate(msg) {
        if (root.isWriting) {
            progressBar.indeterminateText = msg
        }
    }

    // Update isWriting state when write completes
    Connections {
        target: root.imageWriter
        function onSuccess() {
            root.isWriting = false
            root.wizardContainer.isWriting = false
            root.cancelPending = false
            root.isFinalising = false
            root.isComplete = true

            // Calculate final timing stats
            var now = Date.now()
            if (root.verifyPhaseStartTime > 0) {
                root.verifyDurationSecs = (now - root.verifyPhaseStartTime) / 1000
            } else if (root.writePhaseStartTime > 0 && root.writeDurationSecs === 0) {
                // No verification phase, write lasted until now
                root.writeDurationSecs = (now - root.writePhaseStartTime) / 1000
            }

            // Save write statistics to completion snapshot for display on Done screen
            root.wizardContainer.completionSnapshot = {
                // Customization flags
                customizationSupported: root.wizardContainer.customizationSupported,
                hostnameConfigured: root.wizardContainer.hostnameConfigured,
                localeConfigured: root.wizardContainer.localeConfigured,
                userConfigured: root.wizardContainer.userConfigured,
                wifiConfigured: root.wizardContainer.wifiConfigured,
                sshEnabled: root.wizardContainer.sshEnabled,
                piConnectEnabled: root.wizardContainer.piConnectEnabled,
                ifI2cEnabled: root.wizardContainer.ifI2cEnabled,
                ifSpiEnabled: root.wizardContainer.ifSpiEnabled,
                if1WireEnabled: root.wizardContainer.if1WireEnabled,
                ifSerial: root.wizardContainer.ifSerial,
                featUsbGadgetEnabled: root.wizardContainer.featUsbGadgetEnabled,
                // Write statistics
                writeBytesTotal: root.writeBytesTotal,
                writeDurationSecs: root.writeDurationSecs,
                verifyDurationSecs: root.verifyDurationSecs
            }

            // Automatically advance to the done screen
            root.wizardContainer.nextStep()
        }
        function onError(msg) {
            root.isWriting = false
            root.wizardContainer.isWriting = false
            root.cancelPending = false
            root.isFinalising = false
            progressBar.text = qsTr("Write failed: %1").arg(msg)
        }

        function onFinalizing() {
            if (root.isWriting || root.cancelPending) {
                root.isVerifying = false
                root.isFinalising = true
                progressBar.text = qsTr("Finalising…")
                progressBar.value = 100
            }
        }
        
        function onBottleneckStatusChanged(status, throughputKBps) {
            root.bottleneckStatus = status
            root.writeThroughputKBps = throughputKBps
        }
    }
    
    // Focus management - rebuild when visibility changes between phases
    onIsWritingChanged: rebuildFocusOrder()
    onIsCompleteChanged: rebuildFocusOrder()
    onAnyCustomizationsAppliedChanged: rebuildFocusOrder()
    
    Component.onCompleted: {
        // Register summary section as first focus group
        registerFocusGroup("summary", function() {
            var items = []
            if (summaryLayout.visible) {
                // Only include text labels when screen reader is active
                if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                    items.push(summaryHeading)
                    items.push(deviceLabel)
                    items.push(osLabel)
                    items.push(storageLabel)
                }
            }
            return items
        }, 0)
        
        // Register customizations section as second focus group
        registerFocusGroup("customizations", function() {
            var items = []
            if (customLayout.visible) {
                // Only include heading when screen reader is active; always include scroll view
                if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                    items.push(customizationsHeading)
                }
                items.push(customizationsScrollView)
            }
            return items
        }, 1)
        
        // Register progress section (when writing/complete)
        registerFocusGroup("progress", function() {
            var items = []
            if (progressLayout.visible) {
                // Always include progress bar when visible (during writing)
                if (progressBar.visible) {
                    items.push(progressBar)
                }
            }
            return items
        }, 0)
        
        // Let WizardStepBase handle initial focus (title first)
        // Ensure focus order is built when component completes
        Qt.callLater(function() {
            rebuildFocusOrder()
        })
    }
}
