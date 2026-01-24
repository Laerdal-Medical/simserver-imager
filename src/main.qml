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
        if ((wizardContainer.isWriting || wizardContainer.isDownloading) && !forceQuit) {
            close.accepted = false;
            quitDialog.open();
        } else {
            // Cancel any active download before closing
            if (wizardContainer.isDownloading) {
                var repoManager = imageWriter.getRepositoryManager()
                if (repoManager) {
                    repoManager.cancelArtifactInspection()
                }
            }
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

    // Error dialog for displaying application errors
    ErrorDialog {
        id: errorDialog
        imageWriter: window.imageWriter
        parent: overlayRoot

        // Alias for backward compatibility with existing code
        property alias titleText: errorDialog.title

        title: qsTr("Error")
        buttonText: CommonStrings.continueText
        buttonAccessibleDescription: qsTr("Close the error dialog and continue")
    }

    // Warning dialog for storage removal during write
    WarningDialog {
        id: storageRemovedDialog
        imageWriter: window.imageWriter
        parent: overlayRoot

        title: qsTr("Storage device removed")
        message: qsTr("The selected storage device is no longer available. Please reinsert the device or select a different one to continue.")
        buttonText: qsTr("OK")
        buttonAccessibleDescription: qsTr("Close the storage removed notification and return to storage selection")
    }

    // Quit confirmation dialog
    ConfirmDialog {
        id: quitDialog
        imageWriter: window.imageWriter
        parent: overlayRoot

        title: qsTr("Are you sure you want to quit?")
        message: wizardContainer.isWriting
            ? qsTr("Laerdal SimServer Imager is still writing to the storage device. Are you sure you want to quit?")
            : qsTr("Laerdal SimServer Imager is still downloading. Are you sure you want to quit?")
        cancelText: CommonStrings.no
        confirmText: CommonStrings.yes
        cancelAccessibleDescription: qsTr("Return to Laerdal SimServer Imager and continue the current operation")
        confirmAccessibleDescription: qsTr("Force quit Laerdal SimServer Imager and cancel the current write operation")

        onAccepted: {
            // Cancel any active artifact download before quitting
            if (wizardContainer.isDownloading) {
                var repoManager = imageWriter.getRepositoryManager()
                if (repoManager) {
                    repoManager.cancelArtifactInspection()
                }
                wizardContainer.isDownloading = false
            }
            window.forceQuit = true
            Qt.quit()
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
    ConfirmDialog {
        id: elevationDialog
        imageWriter: window.imageWriter
        parent: overlayRoot

        title: qsTr("Administrator Privileges Required")
        message: qsTr("Writing to storage devices requires administrator privileges.\n\nClick 'Restart as Admin' to restart the application with elevated privileges and continue writing.")
        cancelText: qsTr("Cancel")
        confirmText: qsTr("Restart as Admin")
        cancelAccessibleDescription: qsTr("Cancel the write operation")
        confirmAccessibleDescription: qsTr("Restart the application with administrator privileges to write images")

        onAccepted: {
            window.imageWriter.requestElevationForWrite()
        }
    }

    // Permission warning dialog with optional Install Authorization action
    ActionMessageDialog {
        id: permissionWarningDialog
        imageWriter: window.imageWriter
        parent: overlayRoot

        title: qsTr("Permission Warning")
        buttonText: qsTr("OK")

        // Show warning icon in header
        headerIconVisible: true

        // Install Authorization button - only shown for elevatable bundles without policy installed
        secondaryButtonText: qsTr("Install Authorization")
        secondaryButtonVisible: window.imageWriter && window.imageWriter.isElevatableBundle() && !window.imageWriter.hasElevationPolicyInstalled()

        onSecondaryAction: {
            if (window.imageWriter.installElevationPolicy()) {
                permissionWarningDialog.close()
            }
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
