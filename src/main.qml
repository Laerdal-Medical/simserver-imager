/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.Material

import RpiImager

ApplicationWindow {
    id: window
    visible: true

    required property ImageWriter imageWriter

    // Whether to show the landing Language Selection step (set from C++)
    property bool showLanguageSelection: false
    // Wizard manages drive list and selection state
    property bool forceQuit: false
    // Expose overlay root to child components for dialog parenting
    readonly property alias overlayRootItem: overlayRoot

    // Default and minimum sizes
    readonly property int defaultWidth: 800
    readonly property int defaultHeight: 600
    readonly property int minWidth: 800
    readonly property int minHeight: 600

    width: imageWriter.isEmbeddedMode() ? -1 : imageWriter.getIntSetting("window/width", defaultWidth)
    height: imageWriter.isEmbeddedMode() ? -1 : imageWriter.getIntSetting("window/height", defaultHeight)
    minimumWidth: imageWriter.isEmbeddedMode() ? -1 : minWidth
    minimumHeight: imageWriter.isEmbeddedMode() ? -1 : minHeight

    // Track custom repo host for title display
    property string customRepoHost: imageWriter.customRepoHost()
    
    // Track offline state for title display (derived from whether OS list data is available)
    property bool isOffline: imageWriter.isOsListUnavailable
    
    title: {
        var baseTitle = qsTr("Laerdal SimServer Imager %1").arg(imageWriter.constantVersion())
        if (isOffline) {
            baseTitle += " — " + qsTr("Offline")
        }

        if (customRepoHost.length > 0) {
            baseTitle += " — " + qsTr("Using data from %1").arg(customRepoHost)
        }

        return baseTitle
    }

    Component.onCompleted: {
        // Set the main window for modal file dialogs
        imageWriter.setMainWindow(window)
    }

    // Save window size when changed (debounced)
    onWidthChanged: saveWindowSizeTimer.restart()
    onHeightChanged: saveWindowSizeTimer.restart()

    Timer {
        id: saveWindowSizeTimer
        interval: 500  // Debounce to avoid excessive writes during resize
        repeat: false
        onTriggered: {
            if (!window.imageWriter.isEmbeddedMode() && window.width >= window.minWidth && window.height >= window.minHeight) {
                window.imageWriter.setSetting("window/width", window.width)
                window.imageWriter.setSetting("window/height", window.height)
            }
        }
    }

    onClosing: function (close) {
        if (wizardContainer.isWriting && !forceQuit) {
            close.accepted = false;
            quitDialog.open();
        } else {
            // Save window size before closing
            if (!imageWriter.isEmbeddedMode() && window.width >= minWidth && window.height >= minHeight) {
                imageWriter.setSetting("window/width", window.width)
                imageWriter.setSetting("window/height", window.height)
            }
            // allow close
            close.accepted = true;
        }
    }

    // Global overlay to parent/center dialogs across the whole window
    Item {
        id: overlayRoot
        anchors.fill: parent
        z: 1000
    }

    // Keyboard shortcut to export performance data (Ctrl+Shift+P)
    Shortcut {
        sequence: "Ctrl+Shift+P"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (imageWriter.hasPerformanceData()) {
                console.log("Exporting performance data...")
                imageWriter.exportPerformanceData()
            } else {
                console.log("No performance data available to export")
            }
        }
    }
    
    // Secret keyboard shortcut to open debug options (Cmd+Option+S on macOS, Ctrl+Alt+S on others)
    Shortcut {
        sequence: "Ctrl+Alt+S"
        context: Qt.ApplicationShortcut
        onActivated: {
            console.log("Opening debug options dialog...")
            debugOptionsDialog.initialize()
            debugOptionsDialog.open()
        }
    }

    // Main wizard interface
    Rectangle {
        id: wizardBackground
        anchors.fill: parent
        color: Style.mainBackgroundColor

        WizardContainer {
            id: wizardContainer
            anchors.fill: parent
            imageWriter: window.imageWriter
            optionsPopup: appOptionsDialog
            overlayRootRef: overlayRoot
            // Show Language step if C++ requested it
            showLanguageSelection: window.showLanguageSelection

            onWizardCompleted: {
                // Reset to start of wizard or close application
                wizardContainer.currentStep = 0;
            }
        }
    }

    // Modern error dialog (replaces legacy MsgPopup for error/info cases)
    BaseDialog {
        id: errorDialog
        imageWriter: window.imageWriter
        parent: overlayRoot
        anchors.centerIn: parent

        property string titleText: qsTr("Error")
        property string message: ""

        // Custom escape handling
        function escapePressed() {
            errorDialog.close()
        }

        // Register focus groups when component is ready
        Component.onCompleted: {
            registerFocusGroup("content", function(){ 
                // Only include text elements when screen reader is active (otherwise they're not focusable)
                if (errorDialog.imageWriter && errorDialog.imageWriter.isScreenReaderActive()) {
                    return [errorTitle, errorMessage]
                }
                return []
            }, 0)
            registerFocusGroup("buttons", function(){ 
                return [errorContinueButton] 
            }, 1)
        }

        // Dialog content
        Text {
            id: errorTitle
            text: errorDialog.titleText
            font.pixelSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
            Accessible.focusable: errorDialog.imageWriter ? errorDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (errorDialog.imageWriter && errorDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: errorDialog.imageWriter ? errorDialog.imageWriter.isScreenReaderActive() : false
        }

        Text {
            id: errorMessage
            text: errorDialog.message
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            font.pixelSize: Style.fontSizeDescription
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text.replace(/<[^>]+>/g, '')  // Strip HTML tags for accessibility
            Accessible.focusable: errorDialog.imageWriter ? errorDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (errorDialog.imageWriter && errorDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: errorDialog.imageWriter ? errorDialog.imageWriter.isScreenReaderActive() : false
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingMedium
            Item {
                Layout.fillWidth: true
            }
            ImButton {
                id: errorContinueButton
                text: CommonStrings.continueText
                accessibleDescription: qsTr("Close the error dialog and continue")
                activeFocusOnTab: true
                onClicked: errorDialog.close()
            }
        }
    }

    // Specific dialog for storage removal during write
    BaseDialog {
        id: storageRemovedDialog
        imageWriter: window.imageWriter
        parent: overlayRoot
        anchors.centerIn: parent

        // Custom escape handling
        function escapePressed() {
            storageRemovedDialog.close()
        }

        // Register focus groups when component is ready
        Component.onCompleted: {
            registerFocusGroup("content", function(){ 
                // Only include text elements when screen reader is active (otherwise they're not focusable)
                if (storageRemovedDialog.imageWriter && storageRemovedDialog.imageWriter.isScreenReaderActive()) {
                    return [storageRemovedTitle, storageRemovedMessage]
                }
                return []
            }, 0)
            registerFocusGroup("buttons", function(){ 
                return [storageOkButton] 
            }, 1)
        }

        // Dialog content
        Text {
            id: storageRemovedTitle
            text: qsTr("Storage device removed")
            font.pixelSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
            Accessible.focusable: storageRemovedDialog.imageWriter ? storageRemovedDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (storageRemovedDialog.imageWriter && storageRemovedDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: storageRemovedDialog.imageWriter ? storageRemovedDialog.imageWriter.isScreenReaderActive() : false
        }

        Text {
            id: storageRemovedMessage
            text: qsTr("The storage device was removed while writing, so the operation was cancelled. Please reinsert the device or select a different one to continue.")
            wrapMode: Text.WordWrap
            font.pixelSize: Style.fontSizeDescription
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Accessible.focusable: storageRemovedDialog.imageWriter ? storageRemovedDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (storageRemovedDialog.imageWriter && storageRemovedDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: storageRemovedDialog.imageWriter ? storageRemovedDialog.imageWriter.isScreenReaderActive() : false
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingMedium
            Item {
                Layout.fillWidth: true
            }
            ImButtonRed {
                id: storageOkButton
                text: qsTr("OK")
                accessibleDescription: qsTr("Close the storage removed notification and return to storage selection")
                activeFocusOnTab: true
                onClicked: storageRemovedDialog.close()
            }
        }
    }

    // Quit dialog (modern style)
    BaseDialog {
        id: quitDialog
        imageWriter: window.imageWriter
        parent: overlayRoot
        anchors.centerIn: parent

        // Custom escape handling
        function escapePressed() {
            quitDialog.close()
        }

        // Register focus groups when component is ready
        Component.onCompleted: {
            registerFocusGroup("content", function(){ 
                // Only include text elements when screen reader is active (otherwise they're not focusable)
                if (quitDialog.imageWriter && quitDialog.imageWriter.isScreenReaderActive()) {
                    return [quitTitle, quitMessage]
                }
                return []
            }, 0)
            registerFocusGroup("buttons", function(){ 
                return [quitNoButton, quitYesButton] 
            }, 1)
        }

        // Dialog content
        Text {
            id: quitTitle
            text: qsTr("Are you sure you want to quit?")
            font.pixelSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
            Accessible.focusable: quitDialog.imageWriter ? quitDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (quitDialog.imageWriter && quitDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: quitDialog.imageWriter ? quitDialog.imageWriter.isScreenReaderActive() : false
        }

        Text {
            id: quitMessage
            text: qsTr("Laerdal SimServer Imager is still busy. Are you sure you want to quit?")
            font.pixelSize: Style.fontSizeDescription
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Accessible.focusable: quitDialog.imageWriter ? quitDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (quitDialog.imageWriter && quitDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: quitDialog.imageWriter ? quitDialog.imageWriter.isScreenReaderActive() : false
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingMedium
            Item {
                Layout.fillWidth: true
            }

            ImButton {
                id: quitNoButton
                text: CommonStrings.no
                accessibleDescription: qsTr("Return to Laerdal SimServer Imager and continue the current operation")
                activeFocusOnTab: true
                onClicked: quitDialog.close()
            }
            ImButtonRed {
                id: quitYesButton
                text: CommonStrings.yes
                accessibleDescription: qsTr("Force quit Laerdal SimServer Imager and cancel the current write operation")
                activeFocusOnTab: true
                onClicked: {
                    window.forceQuit = true;
                    Qt.quit();
                }
            }
        }
    }

    KeychainPermissionDialog {
        id: keychainpopup
        imageWriter: window.imageWriter
        parent: overlayRoot
        onAccepted: {
            window.imageWriter.keychainPermissionResponse(true);
        }
        onRejected: {
            window.imageWriter.keychainPermissionResponse(false);
        }
    }

    UpdateAvailableDialog {
        id: updatepopup
        imageWriter: window.imageWriter
        // parent can be set to overlayRoot if needed for centering above
        parent: overlayRoot
        onAccepted: {}
        onRejected: {}
    }

    // Elevation request dialog - shown when write operation requires elevated privileges
    BaseDialog {
        id: elevationDialog
        imageWriter: window.imageWriter
        parent: overlayRoot
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape

        // Register focus groups when component is ready
        Component.onCompleted: {
            registerFocusGroup("heading", function(){
                return [elevationHeadingText]
            }, 0)
            registerFocusGroup("message", function(){
                return [elevationMessageText]
            }, 1)
            registerFocusGroup("buttons", function(){
                return [elevateButton, cancelElevationButton]
            }, 2)
        }

        // Dialog content
        Text {
            id: elevationHeadingText
            text: qsTr("Administrator Privileges Required")
            font.pixelSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        Text {
            id: elevationMessageText
            text: qsTr("Writing to storage devices requires administrator privileges.\n\nClick 'Restart as Admin' to restart the application with elevated privileges and continue writing.")
            font.pixelSize: Style.fontSizeDescription
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingMedium
            Item {
                Layout.fillWidth: true
            }

            ImButton {
                id: cancelElevationButton
                text: qsTr("Cancel")
                accessibleDescription: qsTr("Cancel the write operation")
                activeFocusOnTab: true
                onClicked: {
                    elevationDialog.close()
                }
            }

            ImButtonRed {
                id: elevateButton
                text: qsTr("Restart as Admin")
                accessibleDescription: qsTr("Restart the application with administrator privileges to write images")
                activeFocusOnTab: true
                // Make button wide enough to fit the text, with sensible bounds
                Layout.minimumWidth: Style.buttonWidthMinimum
                Layout.maximumWidth: Style.buttonWidthMinimum * 2  // Cap at 2x to handle long translations
                implicitWidth: Math.max(Style.buttonWidthMinimum, implicitContentWidth + leftPadding + rightPadding)
                onClicked: {
                    elevationDialog.close()
                    if (elevationDialog.imageWriter) {
                        elevationDialog.imageWriter.requestElevationForWrite()
                    }
                }
            }
        }
    }

    // Legacy permission warning dialog (kept for backward compatibility with permissionWarning signal)
    BaseDialog {
        id: permissionWarningDialog
        imageWriter: window.imageWriter
        parent: overlayRoot
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape

        property string warningMessage: ""

        function showWarning(message) {
            warningMessage = message
            open()
        }

        Text {
            text: qsTr("Permission Warning")
            font.pixelSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelErrorColor
            Layout.fillWidth: true
        }

        Text {
            text: permissionWarningDialog.warningMessage
            font.pixelSize: Style.fontSizeDescription
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Footer with action buttons
        footer: RowLayout {
            width: parent.width
            height: Style.buttonHeightStandard + (Style.cardPadding * 2)
            spacing: Style.spacingMedium

            // Left padding
            Item { Layout.preferredWidth: Style.cardPadding }

            // Install Authorization button - only shown for elevatable bundles without policy installed
            ImButton {
                id: installAuthButton
                text: qsTr("Install Authorization")
                Layout.preferredHeight: Style.buttonHeightStandard
                activeFocusOnTab: true
                visible: window.imageWriter && window.imageWriter.isElevatableBundle() && !window.imageWriter.hasElevationPolicyInstalled()
                onClicked: {
                    if (window.imageWriter.installElevationPolicy()) {
                        permissionWarningDialog.close()
                    }
                }
            }

            Item { Layout.fillWidth: true }

            ImButton {
                text: qsTr("OK")
                Layout.preferredHeight: Style.buttonHeightStandard
                activeFocusOnTab: true
                onClicked: permissionWarningDialog.close()
            }

            // Right padding
            Item { Layout.preferredWidth: Style.cardPadding }
        }
    }

    AppOptionsDialog {
        id: appOptionsDialog
        parent: overlayRoot
        imageWriter: window.imageWriter
        wizardContainer: wizardContainer
    }

    DebugOptionsDialog {
        id: debugOptionsDialog
        parent: overlayRoot
        imageWriter: window.imageWriter
        wizardContainer: wizardContainer
    }

    // Removed embeddedFinishedPopup; handled by Wizard Done step

    // QML fallback save dialog for performance data export
    ImSaveFileDialog {
        id: performanceSaveDialog
        parent: overlayRoot
        anchors.centerIn: parent
        imageWriter: window.imageWriter
        dialogTitle: qsTr("Save Performance Data")
        nameFilters: [qsTr("JSON files (*.json)"), qsTr("All files (*)")]
        
        onAccepted: {
            var filePath = String(selectedFile)
            // Strip file:// prefix for the C++ call
            if (filePath.indexOf("file://") === 0) {
                filePath = filePath.substring(7)
            }
            if (filePath.length > 0) {
                console.log("Saving performance data to:", filePath)
                imageWriter.exportPerformanceDataToFile(filePath)
            }
        }
    }

    // Handle signal from C++ when native save dialog isn't available
    Connections {
        target: imageWriter
        function onPerformanceSaveDialogNeeded(suggestedFilename, initialDir) {
            console.log("Native save dialog not available, using QML fallback")
            performanceSaveDialog.suggestedFilename = suggestedFilename
            var folderUrl = (Qt.platform.os === "windows") ? ("file:///" + initialDir) : ("file://" + initialDir)
            performanceSaveDialog.currentFolder = folderUrl
            performanceSaveDialog.folder = folderUrl
            performanceSaveDialog.open()
        }
        
        // Update title when custom repository changes
        function onCustomRepoChanged() {
            window.customRepoHost = imageWriter.customRepoHost()
        }
    }

    /* Slots for signals imagewrite emits */
    function onDownloadProgress(now, total) {
        // Forward to wizard container
        wizardContainer.onDownloadProgress(now, total);
    }

    function onWriteProgress(now, total) {
        // Forward to wizard container
        wizardContainer.onWriteProgress(now, total);
    }

    function onVerifyProgress(now, total) {
        // Forward to wizard container
        wizardContainer.onVerifyProgress(now, total);
    }

    function onPreparationStatusUpdate(msg) {
        // Forward to wizard container
        wizardContainer.onPreparationStatusUpdate(msg);
    }

    function onError(msg) {
        errorDialog.titleText = qsTr("Error");
        errorDialog.message = msg;
        errorDialog.open();
    }

    function onFinalizing() {
        wizardContainer.onFinalizing();
    }

    function onCancelled() {
        // Forward to wizard container to handle write cancellation
        if (wizardContainer) {
            wizardContainer.onWriteCancelled();
        }
    }

    function onNetworkInfo(msg) {
        if (imageWriter.isEmbeddedMode() && wizardContainer) {
            wizardContainer.networkInfoText = msg;
        }
    }

    // Called from C++ when selected device is removed
    function onSelectedDeviceRemoved() {
        if (wizardContainer) {
            wizardContainer.selectedStorageName = "";
        }
        imageWriter.setDst("");

        // If we are past storage selection, navigate back there
        if (wizardContainer && wizardContainer.currentStep > wizardContainer.stepStorageSelection) {
            wizardContainer.jumpToStep(wizardContainer.stepStorageSelection);
            // Inform the user with the dedicated modern dialog (only if we navigated back)
            storageRemovedDialog.open();
        }
        // If we're already on storage selection screen, don't show dialog - user can see the device disappeared
    }

    // Called from C++ when a write was cancelled because the storage device was removed
    function onWriteCancelledDueToDeviceRemoval() {
        if (wizardContainer) {
            wizardContainer.isWriting = false;
            wizardContainer.selectedStorageName = "";
        }
        // Clear backend dst reference
        window.imageWriter.setDst("");
        // Navigate back to storage selection for safety
        if (wizardContainer)
            wizardContainer.jumpToStep(wizardContainer.stepStorageSelection);
        // Show dedicated dialog
        storageRemovedDialog.open();
    }

    function onKeychainPermissionRequested() {
        // If warnings are disabled, automatically grant permission without showing dialog
        if (wizardContainer.disableWarnings) {
            window.imageWriter.keychainPermissionResponse(true);
        } else {
            keychainpopup.askForPermission();
        }
    }
    
    
    function onPermissionWarning(message) {
        permissionWarningDialog.showWarning(message);
    }

    function onElevationNeeded() {
        elevationDialog.open();
    }

}
