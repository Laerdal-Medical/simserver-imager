/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

import RpiImager

Item {
    id: root
    
    required property ImageWriter imageWriter
    property var optionsPopup: null
    // Show landing language selection step at startup
    property bool showLanguageSelection: false
    // Reference to the full-window overlay root for dialog parenting
    property var overlayRootRef: null
    // Expose network info text for embedded mode status updates
    property string networkInfoText: ""
    
    // Track whether we have network connectivity (derived from OS list availability)
    // This updates reactively when OS list becomes available after a retry
    readonly property bool hasNetworkConnectivity: !imageWriter.isOsListUnavailable
    
    // Laerdal simplified wizard: Device -> Source -> OS -> Storage -> Writing -> Done
    // NOT a binding, so it won't auto-change when hasNetworkConnectivity changes.
    // The onOsListUnavailableChanged handler manages the offline→online transition.
    property int currentStep: 0
    readonly property int totalSteps: 6
    
    // Track which steps have been made permissible/unlocked for navigation
    // Each bit represents a step: bit 0 = Device, bit 1 = OS, etc.
    property int permissibleStepsBitmap: 1  // Start with Device step (bit 0) always permissible
    
    // Track writing state
    property bool isWriting: false
    
    // Track if we're in "write another" flow (skip to writing step after storage selection)
    property bool writeAnotherMode: false

    // Track if a startup image was provided via command line
    property bool hasStartupImage: false
    
    // Track selections for display in summary
    property string selectedDeviceName: ""
    property string selectedOsName: ""
    property string selectedStorageName: ""
    
    // Track previous selections to detect changes
    property string previousDeviceName: ""
    property string previousOsName: ""

    property bool supportsSerialConsoleOnly: false
    property bool supportsUsbGadget: false
    
    // Track customizations that were actually configured
    property bool hostnameConfigured: false
    property bool localeConfigured: false
    property bool userConfigured: false
    property bool wifiConfigured: false
    property bool sshEnabled: false
    property bool secureBootEnabled: false
    property bool piConnectEnabled: false
    // Whether selected OS supports Remote Connect customization
    property bool piConnectAvailable: false
    // Whether selected OS supports Secure Boot signing
    property bool secureBootAvailable: false
    // Whether secure boot key is configured in App Options
    property bool secureBootKeyConfigured: false

    // Interfaces & Features
    property bool ccRpiAvailable: false
    property bool ifAndFeaturesAvailable: false  // Whether any interface/feature capabilities are available
    property bool ifI2cEnabled: false
    property bool ifSpiEnabled: false
    property bool if1WireEnabled: false
    // "Disabled" | "Default" | "Console & Hardware" | "Console" | "Hardware" | ""
    property string ifSerial: ""
    property bool featUsbGadgetEnabled: false

    // Ephemeral per-run setting: do not persist across runs
    property bool disableWarnings: false
    // Whether the selected OS supports customisation (init_format present)
    // Disabled for Laerdal SimServer Imager - WIC images don't need customization
    property bool customizationSupported: false
    
    // Conserved customization settings object - runtime state passed to generator
    // This is the single source of truth for what customizations will be applied
    // Individual steps read from and write to this object
    property var customizationSettings: ({})
    
    // Snapshot of customization flags captured when write completes, for display on completion screen
    // This readonly snapshot preserves the state even after token/flags are cleared
    property var completionSnapshot: ({
        customizationSupported: false,
        hostnameConfigured: false,
        localeConfigured: false,
        userConfigured: false,
        wifiConfigured: false,
        sshEnabled: false,
        piConnectEnabled: false,
        ifI2cEnabled: false,
        ifSpiEnabled: false,
        if1WireEnabled: false,
        ifSerial: "",
        featUsbGadgetEnabled: false
    })
    
    // Laerdal simplified wizard steps enum
    // Language selection is -1 (special pre-step, only shown when showLanguageSelection is true)
    readonly property int stepLanguageSelection: -1
    readonly property int stepDeviceSelection: 0
    readonly property int stepSourceSelection: 1
    readonly property int stepOSSelection: 2
    readonly property int stepStorageSelection: 3
    readonly property int stepWriting: 4
    readonly property int stepDone: 5

    // SPU flow steps (alternative flow when SPU source is selected)
    readonly property int stepSpuSelection: 10
    readonly property int stepSpuCopy: 11

    // Track if we're in SPU copy mode
    property bool isSpuCopyMode: false
    property string selectedSpuName: ""

    // Legacy step indices (kept for compatibility, mapped to stepWriting)
    readonly property int stepHostnameCustomization: 4
    readonly property int stepLocaleCustomization: 4
    readonly property int stepUserCustomization: 4
    readonly property int stepWifiCustomization: 4
    readonly property int stepRemoteAccess: 4
    readonly property int stepSecureBootCustomization: 4
    readonly property int stepPiConnectCustomization: 4
    readonly property int stepIfAndFeatures: 4
    
    signal wizardCompleted()
    
    // Focus anchor for global keyboard navigation
    Item {
        id: focusAnchor
        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Tab) {
                var currentStep = wizardStack.currentItem
                if (currentStep && typeof currentStep.getNextFocusableElement === 'function') {
                    if (event.modifiers & Qt.ShiftModifier) {
                        var prevElement = currentStep.getPreviousFocusableElement(null)
                        if (prevElement && typeof prevElement.forceActiveFocus === 'function') {
                            prevElement.forceActiveFocus()
                        }
                    } else {
                        var nextElement = currentStep.getNextFocusableElement(null)
                        if (nextElement && typeof nextElement.forceActiveFocus === 'function') {
                            nextElement.forceActiveFocus()
                        }
                    }
                    event.accepted = true
                }
            }
        }
    }

    Component.onCompleted: {
        // Set initial step based on language selection preference and network connectivity at startup.
        // Language selection step is shown first if requested, then device selection (if online) or OS selection (if offline).
        if (showLanguageSelection) {
            currentStep = stepLanguageSelection
        } else if (hasNetworkConnectivity) {
            currentStep = stepDeviceSelection
        } else {
            currentStep = stepOSSelection
        }

        // Default to disabling warnings in embedded mode (per-run, non-persistent)
        if (imageWriter && imageWriter.isEmbeddedMode()) {
            disableWarnings = true
        }

        // Initialize customizationSettings from persistent storage
        // Each step can then read from this and update it as needed
        if (imageWriter) {
            customizationSettings = imageWriter.getSavedCustomisationSettings()

            // Check if secure boot RSA key is configured
            var rsaKeyPath = imageWriter.getStringSetting("secureboot_rsa_key")
            secureBootKeyConfigured = (rsaKeyPath && rsaKeyPath.length > 0)

            // Check if a startup image was passed via command line
            // Set the flag immediately to prevent auto-navigation, then use Qt.callLater
            // to actually process the image after the UI is fully initialized
            var startupUrl = imageWriter.startupImageUrl
            if (startupUrl && startupUrl.toString().length > 0) {
                root.hasStartupImage = true
                Qt.callLater(function() {
                    root.handleStartupImage(startupUrl)
                })
            }
        }
    }
    
    // Handle OS list availability changes
    Connections {
        target: imageWriter
        function onOsListUnavailableChanged() {
            // When OS list becomes available after starting offline, navigate to device
            // selection so the user can choose their target device (now that the list is available).
            // Guard: don't interrupt an active write operation or if a startup image was provided.
            // Check both hasStartupImage flag AND imageWriter.startupImageUrl to handle race conditions.
            var hasStartup = root.hasStartupImage || (imageWriter.startupImageUrl && imageWriter.startupImageUrl.toString().length > 0)
            if (root.hasNetworkConnectivity && root.currentStep === root.stepOSSelection && !root.isWriting && !hasStartup) {
                console.log("OS list now available - navigating to device selection")
                root.jumpToStep(root.stepDeviceSelection)
            }
        }
    }

    // Update selectedDeviceName when hardware device is auto-selected (for startup image flow)
    Connections {
        target: imageWriter ? imageWriter.getHWList() : null
        function onCurrentNameChanged() {
            // When a startup image bypasses device selection, auto-update selectedDeviceName
            if (root.hasStartupImage && root.selectedDeviceName === "") {
                var hwModel = imageWriter.getHWList()
                if (hwModel && hwModel.currentName && hwModel.currentName.length > 0) {
                    root.selectedDeviceName = hwModel.currentName
                    console.log("Auto-set selectedDeviceName from startup image flow:", root.selectedDeviceName)
                }
            }
        }
    }

    // Laerdal simplified wizard step names for sidebar
    readonly property var stepNames: [
        qsTr("Device"),
        qsTr("Source"),
        qsTr("System Image"),
        qsTr("Storage"),
        qsTr("Writing"),
        qsTr("Done")
    ]

    // No customization steps in Laerdal wizard
    readonly property int firstCustomizationStep: stepWriting

    // Helper function to map wizard step to sidebar index
    // Laerdal simplified: direct 1:1 mapping
    function getSidebarIndex(wizardStep) {
        return wizardStep
    }

    // No customization steps in Laerdal wizard
    function getLastCustomizationStep() {
        return stepStorageSelection
    }

    // No customization substeps in Laerdal wizard
    function getCustomizationSubstepLabels() {
        return []
    }

    // No customization substeps in Laerdal wizard
    function isCustomizationSubstepConfigured(subIndex) {
        return false
    }

    // Helper functions for managing permissible steps bitmap
    function markStepPermissible(stepIndex) {
        var bit = 1 << stepIndex
        permissibleStepsBitmap |= bit
    }
    
    function isStepPermissible(stepIndex) {
        var bit = 1 << stepIndex
        return (permissibleStepsBitmap & bit) !== 0
    }
    
    function invalidateStepsFrom(fromStepIndex) {
        // Clear all bits from the specified step onwards
        var mask = (1 << fromStepIndex) - 1  // Keep only bits before fromStepIndex
        permissibleStepsBitmap &= mask
    }
    
    function invalidateDeviceDependentSteps() {
        // When device changes, invalidate all steps after device selection
        invalidateStepsFrom(stepOSSelection)
        
        // Clear device-dependent state
        selectedOsName = ""
        selectedStorageName = ""
        customizationSupported = false  // Disabled for Laerdal SimServer Imager
        
        // Clear all customization flags
        hostnameConfigured = false
        localeConfigured = false
        userConfigured = false
        wifiConfigured = false
        sshEnabled = false
        secureBootEnabled = false
        piConnectEnabled = false
        piConnectAvailable = false
        secureBootAvailable = false
        ccRpiAvailable = false
        ifI2cEnabled = false
        ifSpiEnabled = false
        if1WireEnabled = false
        ifSerial = ""
        featUsbGadgetEnabled = false
    }
    
    function invalidateOSDependentSteps() {
        // When OS changes, invalidate storage and later steps
        invalidateStepsFrom(stepStorageSelection)
        
        // Clear OS-dependent state
        selectedStorageName = ""
        
        // Clear customization flags since they depend on the specific OS
        // The OS selection logic will set customizationSupported appropriately
        // and clear these again if needed, but we clear them proactively here
        hostnameConfigured = false
        localeConfigured = false
        userConfigured = false
        wifiConfigured = false
        sshEnabled = false
        piConnectEnabled = false
        
        // Reset OS capability flags - these will be set correctly by OS selection
        piConnectAvailable = false
        secureBootAvailable = false
        ccRpiAvailable = false
        ifI2cEnabled = false
        ifSpiEnabled = false
        if1WireEnabled = false
        ifSerial = ""
        featUsbGadgetEnabled = false
    }


    // Map sidebar index back to wizard step (1:1 in Laerdal simplified wizard)
    function getWizardStepFromSidebarIndex(sidebarIndex) {
        return sidebarIndex
    }
    
    // Main horizontal layout
    RowLayout {
        anchors.fill: parent
        spacing: 0
        
        // Sidebar
        Rectangle {
            Layout.preferredWidth: Style.sidebarWidth
            Layout.fillHeight: true
            color: Style.sidebarBackgroundColour
            border.color: Style.sidebarBorderColour
            border.width: 0
            
            Flickable {
                id: sidebarScroll
                clip: true
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: sidebarBottom.top
                anchors.margins: Style.cardPadding
                contentWidth: -1
                contentHeight: sidebarColumn.implicitHeight
                z: 1
                boundsBehavior: Flickable.StopAtBounds

                // Touch scrolling improvements
                flickDeceleration: 1500  // Slower deceleration for smoother touch scrolling
                maximumFlickVelocity: 2500  // Reasonable max velocity
                pressDelay: 50  // Brief delay to distinguish tap from scroll on touch

                ColumnLayout {
                    id: sidebarColumn
                    width: parent.width
                    spacing: Style.spacingXSmall
                    // Add right margin when scrollbar is visible to prevent overlap
                    anchors.rightMargin: (sidebarScroll.contentHeight > sidebarScroll.height ? Style.scrollBarWidth : 0)
                
                // Header
                Text {
                    id: sidebarHeader
                    text: qsTr("Setup steps")
                    font.pixelSize: Style.fontSizeHeading
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.sidebarTextOnInactiveColor
                    Layout.fillWidth: true
                    Layout.bottomMargin: Style.spacingSmall
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                
                // Step list
                Repeater {
                    model: root.stepNames
                    
                    Rectangle {
                        id: stepItem
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: (function(){
                            var base = Style.sidebarItemHeight
                            return sublistContainer.visible ? (base + Style.spacingXXSmall + sublistContainer.implicitHeight) : base
                        })()
                        color: Style.transparent
                        border.color: Style.transparent
                        border.width: 0
                        radius: 0
                        property bool isClickable: (function(){
                            if (root.isWriting) return false
                            // If customization not supported, do not allow navigating back to customization group
                            if (!root.customizationSupported && stepItem.index === 3) return false
                            
                            // Get the step index for this sidebar item
                            var targetStep = root.getWizardStepFromSidebarIndex(stepItem.index)
                            
                            // Allow navigation to any permissible step or backward navigation
                            return root.isStepPermissible(targetStep) || targetStep < root.currentStep
                        })()
 
                        // Header band with active background/border
                        Rectangle {
                            id: headerRect
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: Style.sidebarItemHeight
                            color: stepItem.index === root.getSidebarIndex(root.currentStep) ? Style.sidebarActiveBackgroundColor : Style.transparent
                            border.color: stepItem.index === root.getSidebarIndex(root.currentStep) ? Style.sidebarActiveBackgroundColor : Style.transparent
                            border.width: 1
                            radius: root.imageWriter.isEmbeddedMode() ? Style.sidebarItemBorderRadiusEmbedded : Style.sidebarItemBorderRadius
                            antialiasing: true  // Smooth edges at non-integer scale factors
                            clip: true  // Prevent content overflow at non-integer scale factors

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: stepItem.isClickable
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    var targetStep = root.getWizardStepFromSidebarIndex(stepItem.index)
                                    // Guard: skip customization group when unsupported
                                    if (!root.customizationSupported && stepItem.index === 3) {
                                        return
                                    }
                                    // Allow navigation to any permissible step or backward navigation
                                    if (!root.isWriting && (root.isStepPermissible(targetStep) || root.currentStep > targetStep)) {
                                        root.jumpToStep(targetStep)
                                    }
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Style.spacingSmall
                                spacing: Style.spacingTiny
                                MarqueeText {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: stepItem.modelData
                                    font.pixelSize: Style.fontSizeSidebarItem
                                    font.family: Style.fontFamily
                                    color: (stepItem.index > root.getSidebarIndex(root.currentStep) || (stepItem.index === 3 && !root.customizationSupported))
                                               ? Style.formLabelDisabledColor
                                               : (stepItem.index === root.getSidebarIndex(root.currentStep)
                                                   ? Style.sidebarTextOnActiveColor
                                                   : Style.sidebarTextOnInactiveColor)
                                }
                            }
                        }
 
                        // Inline customization sub-steps under the 'Customization' item
                        Column {
                            id: sublistContainer
                            anchors.top: headerRect.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: Style.spacingXXSmall
                            x: Style.spacingExtraLarge
                            width: parent.width - Style.spacingExtraLarge
                            spacing: Style.spacingXXSmall
                            visible: stepItem.index === 3 && root.customizationSupported && root.currentStep > root.stepOSSelection

                            Repeater {
                                model: root.getCustomizationSubstepLabels()
                                Rectangle {
                                    id: subItem
                                    required property int index
                                    required property var modelData
                                    width: sublistContainer ? sublistContainer.width : 0
                                    height: Style.sidebarSubItemHeight
                                    radius: root.imageWriter.isEmbeddedMode() ? Style.sidebarItemBorderRadiusEmbedded : Style.sidebarItemBorderRadius
                                    color: Style.transparent
                                    border.color: Style.transparent
                                    border.width: 0
                                    antialiasing: true  // Smooth edges at non-integer scale factors

                                    property bool isCurrentStep: {
                                        if (root.currentStep < root.firstCustomizationStep || root.currentStep > root.getLastCustomizationStep()) {
                                            return false
                                        }
                                        
                                        // Map current step to display index by finding which label matches
                                        var labels = root.getCustomizationSubstepLabels()
                                        if (subItem.index >= labels.length) return false
                                        
                                        var currentStepLabel = ""
                                        if (root.currentStep === root.stepHostnameCustomization) currentStepLabel = qsTr("Hostname")
                                        else if (root.currentStep === root.stepLocaleCustomization) currentStepLabel = qsTr("Localisation")
                                        else if (root.currentStep === root.stepUserCustomization) currentStepLabel = qsTr("User")
                                        else if (root.currentStep === root.stepWifiCustomization) currentStepLabel = qsTr("Wi‑Fi")
                                        else if (root.currentStep === root.stepRemoteAccess) currentStepLabel = qsTr("Remote access")
                                        else if (root.currentStep === root.stepPiConnectCustomization) currentStepLabel = qsTr("Remote Connect")
                                        else if (root.currentStep === root.stepIfAndFeatures) currentStepLabel = qsTr("Interfaces & Features")
                                        
                                        return labels[subItem.index] === currentStepLabel
                                    }
                                    property bool isConfigured: root.isCustomizationSubstepConfigured(subItem.index)
                                    property bool isClickable: root.customizationSupported && !root.isWriting && root.currentStep > root.stepOSSelection && (
                                        // Allow navigation to any substep if we've reached customization
                                        root.currentStep >= root.firstCustomizationStep ||
                                        // Or if we've been to customization before (any substep configured)
                                        root.hostnameConfigured || root.localeConfigured || root.userConfigured || 
                                        root.wifiConfigured || root.sshEnabled || root.piConnectEnabled ||
                                        // Or if any customization step has been made permissible
                                        root.isStepPermissible(root.stepHostnameCustomization) ||
                                        root.isStepPermissible(root.stepLocaleCustomization) ||
                                        root.isStepPermissible(root.stepUserCustomization) ||
                                        root.isStepPermissible(root.stepWifiCustomization) ||
                                        root.isStepPermissible(root.stepRemoteAccess) ||
                                        root.isStepPermissible(root.stepPiConnectCustomization) ||
                                        root.isStepPermissible(root.stepIfAndFeatures)
                                    )

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: subItem.isClickable
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            // Map display index to actual step index based on available labels
                                            var labels = root.getCustomizationSubstepLabels()
                                            if (subItem.index >= labels.length) return
                                            
                                            var stepLabel = labels[subItem.index]
                                            var target = root.firstCustomizationStep // default to hostname
                                            
                                            if (stepLabel === qsTr("Hostname")) target = root.stepHostnameCustomization
                                            else if (stepLabel === qsTr("Localisation")) target = root.stepLocaleCustomization
                                            else if (stepLabel === qsTr("User")) target = root.stepUserCustomization
                                            else if (stepLabel === qsTr("Wi‑Fi")) target = root.stepWifiCustomization
                                            else if (stepLabel === qsTr("Remote access")) target = root.stepRemoteAccess
                                            else if (stepLabel === qsTr("Remote Connect")) target = root.stepPiConnectCustomization
                                            else if (stepLabel === qsTr("Interfaces & Features")) target = root.stepIfAndFeatures
                                            
                                            // Allow navigation to permissible steps or backward navigation within customization
                                            if (root.currentStep !== target && (root.isStepPermissible(target) || target < root.currentStep)) {
                                                root.jumpToStep(target)
                                            }
                                        }
                                    }
                                    RowLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: Style.spacingSmall
                                        anchors.leftMargin: Style.spacingMedium
                                        MarqueeText {
                                            id: subLabel
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: subItem.modelData
                                            font.pixelSize: Style.fontSizeCaption
                                            font.family: Style.fontFamily
                                            font.bold: subItem.isConfigured
                                            font.underline: subItem.isCurrentStep
                                            color: (!root.customizationSupported || !subItem.isClickable)
                                                       ? Style.formLabelDisabledColor
                                                       : Style.sidebarTextOnInactiveColor
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Spacer
                Item {
                    Layout.fillHeight: true
                }
                
                // [moved] Advanced options lives outside the scroll area
                }
                ScrollBar.vertical: ScrollBar { 
                    width: Style.scrollBarWidth
                    policy: ScrollBar.AsNeeded 
                }
            }
            // Fixed bottom container for Advanced Options
            Item {
                id: sidebarBottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Style.cardPadding
                anchors.rightMargin: Style.cardPadding
                anchors.bottomMargin: Style.spacingSmall
                height: Style.buttonHeightStandard
                z: 2

                ImButton {
                    id: optionsButton
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Style.buttonHeightStandard
                    text: qsTr("App Options")
                    accessibleDescription: qsTr("Open application settings to configure sound alerts, auto-eject, telemetry, and content repository")
                    activeFocusOnTab: true
                    onClicked: {
                        if (root.optionsPopup) {
                            if (!root.optionsPopup.wizardContainer) {
                                root.optionsPopup.wizardContainer = root
                            }
                            // TODO: actually duplicate
                            // as onOpen in it already calls initialize()
                            root.optionsPopup.initialize()
                            root.optionsPopup.open()
                        }
                    }
                }
            }
        }
        // Vertical separator between sidebar and content
        Item {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height * 0.75
                color: Style.titleSeparatorColor
            }
        }

        // Main content area
        StackView {
            id: wizardStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            // Laerdal simplified: always start with device selection
            initialItem: root.showLanguageSelection ? languageSelectionStep : deviceSelectionStep
            
            // Smooth transitions between steps
            pushEnter: Transition {
                PropertyAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 250
                }
            }
            
            pushExit: Transition {
                PropertyAnimation {
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: 250
                }
            }
            
            popEnter: Transition {
                PropertyAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 250
                }
            }
            
            popExit: Transition {
                PropertyAnimation {
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: 250
                }
            }
            
            // Set focus when a new step is activated
            onCurrentItemChanged: {
                if (currentItem) {
                    Qt.callLater(function() {
                        if (currentItem && currentItem.initialFocusItem) {
                            currentItem.initialFocusItem.forceActiveFocus()
                        } else if (currentItem) {
                            // Fallback: try to find first focusable field
                            if (currentItem._focusableItems && currentItem._focusableItems.length > 0) {
                                currentItem._focusableItems[0].forceActiveFocus()
                            }
                        }
                    })
                }
            }
        }
    }
    
    // Navigation functions - Laerdal simplified (no customization steps)
    function nextStep() {
        if (root.currentStep < root.totalSteps - 1) {
            var nextIndex = root.currentStep + 1

            // Special handling for "write another" mode: skip directly to writing step after storage selection
            if (writeAnotherMode && root.currentStep === stepStorageSelection) {
                nextIndex = stepWriting
                writeAnotherMode = false  // Reset the flag
            }

            // SPU mode routing: after storage selection, go to SPU copy step instead of writing
            if (root.isSpuCopyMode && root.currentStep === stepStorageSelection) {
                nextIndex = stepSpuCopy
            }

            root.currentStep = nextIndex
            var nextComponent = getStepComponent(root.currentStep)
            if (nextComponent) {
                // Destroy previous step to avoid lingering handlers, then show the next step
                wizardStack.clear()
                wizardStack.push(nextComponent)
            }
        }
    }
    
    // Simplified previousStep - no customization steps to skip
    function previousStep() {
        if (root.currentStep > 0) {
            var prevIndex = root.currentStep - 1
            root.currentStep = prevIndex
            var prevComponent = getStepComponent(root.currentStep)
            if (prevComponent) {
                // Clear and push the previous step explicitly since we keep a single-item stack
                wizardStack.clear()
                wizardStack.push(prevComponent)
            }
        }
    }
    
    function jumpToStep(stepIndex) {
        if (stepIndex >= 0 && stepIndex < root.totalSteps) {
            root.currentStep = stepIndex
            var stepComponent = getStepComponent(stepIndex)
            if (stepComponent) {
                // Clear the stack and push the target step
                wizardStack.clear()
                wizardStack.push(stepComponent)
            }
        }
    }

    // Check if "Use custom" device is selected (for local WIC file selection)
    function isUseCustomSelected() {
        var hwModel = root.imageWriter.getHWList()
        if (!hwModel || hwModel.currentIndex < 0) return false
        var currentName = hwModel.currentName
        return currentName === qsTr("Use custom")
    }

    // Open file dialog for custom WIC file selection
    function openCustomFileDialog() {
        // Use native file dialog if available, otherwise fall back to QML FileDialog
        if (root.imageWriter.nativeFileDialogAvailable()) {
            Qt.callLater(function() {
                root.imageWriter.openFileDialog(CommonStrings.imageFiltersString, false)
            })
        } else {
            // Use QML fallback dialog - it remembers the last folder automatically
            customImageFileDialog.dialogTitle = qsTr("Select image")
            customImageFileDialog.nameFilters = CommonStrings.imageFiltersList
            customImageFileDialog.open()
        }
    }

    // Fallback QML file dialog when native dialogs are unavailable
    ImFileDialog {
        id: customImageFileDialog
        imageWriter: root.imageWriter
        parent: root.overlayRootRef ? root.overlayRootRef : root
        anchors.centerIn: parent
        nameFilters: CommonStrings.imageFiltersList
        onAccepted: {
            if (selectedFile && String(selectedFile).length > 0) {
                root.handleCustomFileSelected(selectedFile)
            }
        }
    }

    // Handle file selection for "Use custom" flow (from both native and fallback dialogs)
    function handleCustomFileSelected(fileUrl) {
        if (root.isUseCustomSelected() && root.currentStep === root.stepDeviceSelection && fileUrl.toString().length > 0) {
            // Set the source to the selected file
            root.imageWriter.setSrc(fileUrl)
            root.selectedOsName = root.imageWriter.srcFileName()
            root.customizationSupported = false  // Disabled for Laerdal SimServer Imager
            // Skip Source and OS steps, go directly to Storage
            root.jumpToStep(root.stepStorageSelection)
        }
    }

    // Handle startup image file passed as command line argument
    function handleStartupImage(fileUrl) {
        if (fileUrl && fileUrl.toString().length > 0) {
            // Mark that we have a startup image to prevent auto-navigation
            root.hasStartupImage = true

            var urlStr = fileUrl.toString().toLowerCase()
            var isSpu = urlStr.endsWith(".spu")

            if (isSpu) {
                // SPU file - set up SPU copy mode (copies file to USB, not disk write)
                console.log("SPU file passed as startup argument:", fileUrl)
                root.imageWriter.setSrcSpuFile(fileUrl.toString().replace("file://", ""))
                root.selectedOsName = root.imageWriter.srcFileName()
                root.isSpuCopyMode = true
                root.customizationSupported = false
            } else {
                // Regular WIC/VSI disk image
                root.imageWriter.setSrc(fileUrl)
                root.selectedOsName = root.imageWriter.srcFileName()
                root.isSpuCopyMode = false
                root.customizationSupported = false  // Disabled for Laerdal SimServer Imager
            }

            // Mark previous steps as permissible so user can navigate back
            root.permissibleStepsBitmap |= (1 << root.stepSourceSelection)
            root.permissibleStepsBitmap |= (1 << root.stepOSSelection)
            // Go directly to Storage selection
            root.jumpToStep(root.stepStorageSelection)
        }
    }

    // Handle file selection from native dialog for "Use custom" flow
    Connections {
        target: root.imageWriter
        function onFileSelected(fileUrl) {
            root.handleCustomFileSelected(fileUrl)
        }
    }

    // Laerdal simplified wizard step components
    function getStepComponent(stepIndex) {
        switch(stepIndex) {
            case stepLanguageSelection: return languageSelectionStep
            case stepDeviceSelection: return deviceSelectionStep
            case stepSourceSelection: return sourceSelectionStep
            case stepOSSelection: return osSelectionStep
            case stepStorageSelection: return storageSelectionStep
            case stepWriting: return writingStep
            case stepDone: return doneStep
            // SPU flow steps
            case stepSpuSelection: return spuSelectionStep
            case stepSpuCopy: return spuCopyStep
            default: return null
        }
    }
    
    // Step components
    Component {
        id: languageSelectionStep
        LanguageSelectionStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: {
                // After choosing language, jump to device selection
                root.jumpToStep(root.stepDeviceSelection)
            }
        }
    }
    Component {
        id: deviceSelectionStep
        DeviceSelectionStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            showBackButton: false
            appOptionsButton: optionsButton
            onNextClicked: {
                // If "Use custom" is selected, open file dialog instead of going to next step
                if (isUseCustomSelected()) {
                    openCustomFileDialog()
                } else {
                    root.nextStep()
                }
            }
        }
    }

    Component {
        id: sourceSelectionStep
        SourceSelectionStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
        }
    }

    Component {
        id: osSelectionStep
        OSSelectionStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            showBackButton: true
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
        }
    }
    
    Component {
        id: storageSelectionStep
        StorageSelectionStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
        }
    }
    
    Component {
        id: hostnameCustomizationStep
        HostnameCustomizationStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
            onSkipClicked: {
                // Skip functionality is handled in the step itself
            }
        }
    }
    
    Component {
        id: localeCustomizationStep
        LocaleCustomizationStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
            onSkipClicked: {
                // Skip functionality is handled in the step itself
            }
        }
    }
    
    Component {
        id: userCustomizationStep
        UserCustomizationStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
            onSkipClicked: {
                // Skip functionality is handled in the step itself
            }
        }
    }
    
    Component {
        id: wifiCustomizationStep
        WifiCustomizationStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
            onSkipClicked: {
                // Skip functionality is handled in the step itself
            }
        }
    }
    
    Component {
        id: remoteAccessStep
        RemoteAccessStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
            onSkipClicked: {
                // Skip functionality is handled in the step itself
            }
        }
    }
    
    Component {
        id: secureBootCustomizationStep
        SecureBootCustomizationStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
            onSkipClicked: {
                // Skip functionality is handled in the step itself
            }
        }
    }

    Component {
        id: piConnectCustomizationStep
        PiConnectCustomizationStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: {
                // Only advance if the step indicates it's ready
                if (isValid) {
                    root.nextStep()
                }
                // Otherwise, let the step handle the action internally (showing dialog, etc.)
            }
            onBackClicked: root.previousStep()
            onSkipClicked: {
                // Skip functionality is handled in the step itself
            }
        }
    }

    Component {
        id: ifAndFeaturesStep
        IfAndFeaturesCustomizationStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: {
                // Only advance if the step indicates it's ready
                if (isConfirmed) {
                    root.nextStep()
                }
                // Otherwise, let the step handle the action internally
            }
            onBackClicked: root.previousStep()
            onSkipClicked: {
                // Skip functionality is handled in the step itself
            }
        }
    }
    
    Component {
        id: writingStep
        WritingStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            showBackButton: true
            appOptionsButton: optionsButton
            // Let WritingStep handle its own button text based on state
            onNextClicked: {
                // Only advance if the step indicates it's ready
                if (isComplete) {
                    root.nextStep()
                }
                // Otherwise, let the step handle the action internally
            }
            onBackClicked: root.previousStep()
        }
    }
    
    Component {
        id: doneStep
        DoneStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            showBackButton: false
            nextButtonText: CommonStrings.finish
            appOptionsButton: optionsButton
            onNextClicked: root.wizardCompleted()
        }
    }

    // SPU flow step components
    Component {
        id: spuSelectionStep
        SPUSelectionStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: {
                // After SPU selection, go to storage selection, then SPU copy
                root.jumpToStep(root.stepStorageSelection)
            }
            onBackClicked: {
                // Go back to source selection
                root.isSpuCopyMode = false
                root.jumpToStep(root.stepSourceSelection)
            }
        }
    }

    Component {
        id: spuCopyStep
        SPUCopyStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: {
                if (isComplete || hasError) {
                    // Go to done step
                    root.jumpToStep(root.stepDone)
                }
            }
            onBackClicked: {
                // Go back to storage selection
                root.jumpToStep(root.stepStorageSelection)
            }
        }
    }

    // Token conflict dialog — based on your BaseDialog pattern
    BaseDialog {
        id: tokenConflictDialog
        imageWriter: root.imageWriter
        parent: root
        anchors.centerIn: parent

        // carry the new token we just received
        property string newToken: ""
        property bool allowAccept: false

        // small safety delay before enabling "Replace"
        Timer {
            id: acceptEnableDelay
            interval: 1500
            running: false
            repeat: false
            onTriggered: {
                tokenConflictDialog.allowAccept = true
                // Rebuild focus order now that replace button is enabled
                tokenConflictDialog.rebuildFocusOrder()
            }
        }

        function openWithToken(tok) {
            newToken = tok
            allowAccept = false
            acceptEnableDelay.start()
            tokenConflictDialog.open()
        }

        // ESC closes
        function escapePressed() { tokenConflictDialog.close() }

        Component.onCompleted: {
            // match your focus group style
            registerFocusGroup("token_conflict_content", function() {
                // Only include text elements when screen reader is active (otherwise they're not focusable)
                if (tokenConflictDialog.imageWriter && tokenConflictDialog.imageWriter.isScreenReaderActive()) {
                    return [titleText, bodyText]
                }
                return []
            }, 0)
            registerFocusGroup("token_conflict_buttons", function() {
                return [keepBtn, replaceBtn]
            }, 1)
        }

        onClosed: {
            acceptEnableDelay.stop()
            allowAccept = false
            newToken = ""
        }

        // ----- CONTENT -----
        Text {
            id: titleText
            text: qsTr("Replace existing Remote Connect token?")
            font.pixelSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
            Accessible.ignored: false
            Accessible.focusable: tokenConflictDialog.imageWriter ? tokenConflictDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (tokenConflictDialog.imageWriter && tokenConflictDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: tokenConflictDialog.imageWriter ? tokenConflictDialog.imageWriter.isScreenReaderActive() : false
        }

        // Body / security note
        Text {
            id: bodyText
            text: qsTr("A new Remote Connect token was received that differs from your current one.\n\n") +
                  qsTr("Do you want to overwrite the existing token?\n\n") +
                  qsTr("Warning: Only overwrite the token if you initiated this action.")
            font.pixelSize: Style.fontSizeFormLabel
            font.family: Style.fontFamily
            color: Style.formLabelColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Accessible.ignored: false
            Accessible.focusable: tokenConflictDialog.imageWriter ? tokenConflictDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (tokenConflictDialog.imageWriter && tokenConflictDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: tokenConflictDialog.imageWriter ? tokenConflictDialog.imageWriter.isScreenReaderActive() : false
        }

        // Buttons row
        RowLayout {
            id: btnRow
            Layout.fillWidth: true
            Layout.topMargin: Style.spacingSmall
            spacing: Style.spacingMedium

            Item { Layout.fillWidth: true }

            ImButton {
                id: replaceBtn
                text: tokenConflictDialog.allowAccept ? qsTr("Replace token") : qsTr("Please wait…")
                accessibleDescription: qsTr("Replace the current token with the newly received one")
                enabled: tokenConflictDialog.allowAccept
                activeFocusOnTab: true
                onClicked: {
                    tokenConflictDialog.close()
                    // Overwrite in C++ and re-emit to existing listeners
                    root.imageWriter.overwriteConnectToken(tokenConflictDialog.newToken)
                }
            }

            ImButtonRed {
                id: keepBtn
                text: qsTr("Keep existing")
                accessibleDescription: qsTr("Keep your current Remote Connect token")
                activeFocusOnTab: true
                onClicked: tokenConflictDialog.close()
            }
        }
    }

    Connections {
        target: root.imageWriter
        function onConnectTokenConflictDetected(newToken) {
            tokenConflictDialog.openWithToken(newToken)
        }
        
        // Handle token cleared signal at container level to ensure it's always processed
        // even when PiConnectCustomizationStep component is not loaded
        function onConnectTokenCleared() {
            // Reset Pi Connect state when token is cleared (e.g., after write completes)
            // Note: Snapshot is already captured when entering writing step, so no need to capture here
            piConnectEnabled = false
            delete customizationSettings.piConnectEnabled
        }
        
        // Handle repository URL received from deep link (laerdal-imager://open?repo=...)
        function onRepositoryUrlReceived(url) {
            repositoryUrlDialog.openWithUrl(url)
        }
    }

    // Repository URL confirmation dialog — shown when a deep link contains a custom repo URL
    BaseDialog {
        id: repositoryUrlDialog
        imageWriter: root.imageWriter
        parent: root
        anchors.centerIn: parent

        // carry the repository URL we just received
        property string repoUrl: ""
        property bool allowAccept: false
        property bool isLocalFile: repoUrl.startsWith("file://")

        // small safety delay before enabling "Switch" (only for remote URLs)
        Timer {
            id: repoAcceptEnableDelay
            interval: 1500
            running: false
            repeat: false
            onTriggered: {
                repositoryUrlDialog.allowAccept = true
                // Rebuild focus order now that switch button is enabled
                repositoryUrlDialog.rebuildFocusOrder()
            }
        }

        function openWithUrl(url) {
            // If dialog is already open with a different URL, ignore the new one
            // User must dismiss current dialog first (prevents race condition attacks)
            if (repositoryUrlDialog.opened && repoUrl !== url) {
                console.warn("Repository dialog already open, ignoring new URL:", url)
                return
            }
            
            repoUrl = url
            // Local files are trusted, allow immediate acceptance
            if (url.startsWith("file://")) {
                allowAccept = true
            } else {
                allowAccept = false
                repoAcceptEnableDelay.start()
            }
            repositoryUrlDialog.open()
        }

        // ESC closes
        function escapePressed() { repositoryUrlDialog.close() }

        Component.onCompleted: {
            // match your focus group style
            registerFocusGroup("repo_url_content", function() {
                // Only include text elements when screen reader is active (otherwise they're not focusable)
                if (repositoryUrlDialog.imageWriter && repositoryUrlDialog.imageWriter.isScreenReaderActive()) {
                    return [repoTitleText, repoBodyText, repoUrlText]
                }
                return []
            }, 0)
            registerFocusGroup("repo_url_buttons", function() {
                return [repoCancelBtn, repoSwitchBtn]
            }, 1)
        }

        onClosed: {
            repoAcceptEnableDelay.stop()
            allowAccept = false
            repoUrl = ""
        }

        // ----- CONTENT -----
        Text {
            id: repoTitleText
            text: repositoryUrlDialog.isLocalFile 
                ? qsTr("Open local repository file?")
                : qsTr("Switch to a custom repository?")
            font.pixelSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
            Accessible.ignored: false
            Accessible.focusable: repositoryUrlDialog.imageWriter ? repositoryUrlDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (repositoryUrlDialog.imageWriter && repositoryUrlDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: repositoryUrlDialog.imageWriter ? repositoryUrlDialog.imageWriter.isScreenReaderActive() : false
        }

        // Body / security note
        Text {
            id: repoBodyText
            text: repositoryUrlDialog.isLocalFile
                ? qsTr("You are opening a local Laerdal Imager manifest file. This will replace the current OS list with the contents of this file.")
                : qsTr("A website is requesting to switch Laerdal SimServer Imager to use a custom OS repository.\n\n") +
                  qsTr("Only accept if you trust this source and intentionally clicked a link to open this repository.")
            font.pixelSize: Style.fontSizeFormLabel
            font.family: Style.fontFamily
            color: Style.formLabelColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Accessible.ignored: false
            Accessible.focusable: repositoryUrlDialog.imageWriter ? repositoryUrlDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (repositoryUrlDialog.imageWriter && repositoryUrlDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: repositoryUrlDialog.imageWriter ? repositoryUrlDialog.imageWriter.isScreenReaderActive() : false
        }
        
        // Show the URL being requested
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacingSmall
            Layout.preferredHeight: repoUrlText.implicitHeight + Style.spacingSmall * 2
            color: Style.titleBackgroundColor
            border.color: Style.popupBorderColor
            border.width: 1
            radius: Style.listItemBorderRadius
            
            Text {
                id: repoUrlText
                anchors.fill: parent
                anchors.margins: Style.spacingSmall
                text: repositoryUrlDialog.repoUrl
                font.pixelSize: Style.fontSizeCaption
                font.family: "monospace"
                color: Style.formLabelColor
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideMiddle
                maximumLineCount: 3
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("Repository URL: %1").arg(repositoryUrlDialog.repoUrl)
                Accessible.ignored: false
                Accessible.focusable: repositoryUrlDialog.imageWriter ? repositoryUrlDialog.imageWriter.isScreenReaderActive() : false
                focusPolicy: (repositoryUrlDialog.imageWriter && repositoryUrlDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                activeFocusOnTab: repositoryUrlDialog.imageWriter ? repositoryUrlDialog.imageWriter.isScreenReaderActive() : false
            }
        }

        // Buttons row
        RowLayout {
            id: repoBtnRow
            Layout.fillWidth: true
            Layout.topMargin: Style.spacingSmall
            spacing: Style.spacingMedium

            Item { Layout.fillWidth: true }

            ImButton {
                id: repoSwitchBtn
                text: {
                    if (!repositoryUrlDialog.allowAccept) return qsTr("Please wait…")
                    return repositoryUrlDialog.isLocalFile ? qsTr("Open") : qsTr("Switch repository")
                }
                accessibleDescription: repositoryUrlDialog.isLocalFile
                    ? qsTr("Open the local manifest file and use it as the OS repository")
                    : qsTr("Switch to the custom repository from the link")
                enabled: repositoryUrlDialog.allowAccept
                activeFocusOnTab: true
                onClicked: {
                    repositoryUrlDialog.close()
                    // Switch to the new repository and reset wizard
                    // QML auto-converts string to QUrl for C++ method
                    root.imageWriter.refreshOsListFrom(repositoryUrlDialog.repoUrl)
                    root.resetWizard()
                }
            }

            ImButtonRed {
                id: repoCancelBtn
                text: qsTr("Cancel")
                accessibleDescription: qsTr("Keep your current repository settings")
                activeFocusOnTab: true
                onClicked: repositoryUrlDialog.close()
            }
        }
    }

    
    function onFinalizing() {
        // Forward to the WritingStep if currently active
        if (currentStep === stepWriting && wizardStack.currentItem) {
            wizardStack.currentItem.onFinalizing()
        }
    }
    
    function onWriteCancelled() {
        // Reset write state
        isWriting = false
        
        // Navigate back to writing step (which will show the summary since isWriting is false)
        if (currentStep !== stepWriting) {
            jumpToStep(stepWriting)
        }
        
        // Reset the writing step's state if it exists
        if (wizardStack.currentItem && wizardStack.currentItem.objectName === "writingStep") {
            wizardStack.currentItem.isWriting = false
            wizardStack.currentItem.cancelPending = false
            wizardStack.currentItem.isFinalising = false
            wizardStack.currentItem.isComplete = false
        }
    }
    
    function onDownloadProgress(now, total) {
        // Forward to the WritingStep if currently active
        if (currentStep === stepWriting && wizardStack.currentItem) {
            wizardStack.currentItem.onDownloadProgress(now, total)
        }
    }
    
    function onWriteProgress(now, total) {
        // Forward to the WritingStep if currently active
        if (currentStep === stepWriting && wizardStack.currentItem) {
            wizardStack.currentItem.onWriteProgress(now, total)
        }
    }
    
    function onVerifyProgress(now, total) {
        // Forward to the WritingStep if currently active
        if (currentStep === stepWriting && wizardStack.currentItem) {
            wizardStack.currentItem.onVerifyProgress(now, total)
        }
    }
    
    function onPreparationStatusUpdate(msg) {
        // Forward to the WritingStep if currently active
        if (currentStep === stepWriting && wizardStack.currentItem) {
            wizardStack.currentItem.onPreparationStatusUpdate(msg)
        }
    }
    
    function resetWizard() {
        // Reset all wizard state to initial values - Laerdal simplified
        currentStep = 0
        permissibleStepsBitmap = 1  // Reset to only Device step permissible
        isWriting = false
        writeAnotherMode = false
        selectedDeviceName = ""
        selectedOsName = ""
        selectedStorageName = ""
        previousDeviceName = ""
        previousOsName = ""

        // Reset hardware model selection to prevent stale state
        if (imageWriter) {
            var hwModel = imageWriter.getHWList()
            if (hwModel) {
                hwModel.currentIndex = -1
            }
            // Also clear ImageWriter's internal source and destination state
            imageWriter.setSrc("")
            imageWriter.setDst("", 0)
        }

        // Navigate back to device selection
        wizardStack.clear()
        wizardStack.push(deviceSelectionStep)
    }
    
    function resetToWriteStep() {
        // Reset only the storage selection to allow choosing a new storage device
        // while preserving device, OS settings
        selectedStorageName = ""

        // Keep all steps permissible - they've already been completed
        // This allows backward navigation if needed

        // Enable write another mode to skip directly to writing step after storage selection
        writeAnotherMode = true

        // Navigate to storage selection step so user can select a new SD card
        currentStep = stepStorageSelection
        wizardStack.clear()
        wizardStack.push(storageSelectionStep)
    }

    // Detect device selection changes and invalidate dependent steps
    onSelectedDeviceNameChanged: {
        if (previousDeviceName !== "" && previousDeviceName !== selectedDeviceName) {
            console.log("Device changed from", previousDeviceName, "to", selectedDeviceName, "- invalidating dependent steps")
            invalidateDeviceDependentSteps()
        }
        previousDeviceName = selectedDeviceName
    }
    
    // Detect OS selection changes and invalidate dependent steps
    onSelectedOsNameChanged: {
        if (previousOsName !== "" && previousOsName !== selectedOsName) {
            console.log("OS changed from", previousOsName, "to", selectedOsName, "- invalidating dependent steps")
            invalidateOSDependentSteps()
        }
        previousOsName = selectedOsName
    }

    // Keep customization items visible when navigating within customization
    onCurrentStepChanged: {
        // Mark the current step as permissible for future navigation
        markStepPermissible(currentStep)
        
        if (!sidebarScroll) return
        if (currentStep >= firstCustomizationStep && currentStep <= getLastCustomizationStep()) {
            var idx = currentStep - firstCustomizationStep
            var mainRowH = Style.sidebarItemHeight + Style.spacingXSmall
            var subRectH = Style.sidebarSubItemHeight
            var subRowH = subRectH + Style.spacingXXSmall
            var baseY = sidebarHeader.y + sidebarHeader.implicitHeight + Style.spacingSmall + mainRowH * (3 + 1) + Style.spacingXXSmall
            var target = baseY + idx * subRowH - (sidebarScroll.height/2 - subRectH/2)
            if (target < 0) target = 0
            var maxY = sidebarScroll.contentHeight - sidebarScroll.height
            if (target > maxY) target = Math.max(0, maxY)
            sidebarScroll.contentY = target
        } else {
            // Center main group item
            var sidebarIdx = getSidebarIndex(currentStep)
            var mainRowH = Style.sidebarItemHeight + Style.spacingXSmall
            // account for header and its bottom margin
            var target2 = sidebarHeader.y + sidebarHeader.implicitHeight + Style.spacingSmall + sidebarIdx * mainRowH - (sidebarScroll.height/2 - Style.sidebarItemHeight/2)
            if (target2 < 0) target2 = 0
            var maxY2 = sidebarScroll.contentHeight - sidebarScroll.height
            if (target2 > maxY2) target2 = Math.max(0, maxY2)
            sidebarScroll.contentY = target2
        }
    }
} 
