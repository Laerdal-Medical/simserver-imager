/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import RpiImager

WizardStepBase {
    id: root
    
    required property ImageWriter imageWriter
    required property var wizardContainer
    
    readonly property HWListModel hwmodel: imageWriter.getHWList()
    readonly property OSListModel osmodel: imageWriter.getOSList()
    
    title: qsTr("Choose system image")
    subtitle: qsTr("Select a system image to install on your device")
    showNextButton: true
    // Disable Next until a concrete OS has been selected
    nextButtonEnabled: oslist.currentIndex !== -1 && wizardContainer.selectedOsName.length > 0
    
    property alias oslist: oslist
    property alias osswipeview: osswipeview
    property string categorySelected: ""
    property bool modelLoaded: false
    // Track if a custom local image has been chosen in this step
    property bool customSelected: false
    property real customSelectedSize: 0
    
    // Property to trigger cache status re-evaluation when cache changes
    property int cacheStatusVersion: 0
    
    // Connect to cache status changes
    Connections {
        target: imageWriter
        function onCacheStatusChanged() {
            // Save scroll position before updating cache status (which causes all delegates to re-evaluate)
            var savedContentY = oslist.contentY
            root.cacheStatusVersion++
            // Restore scroll position after cache status update
            Qt.callLater(function() {
                oslist.contentY = savedContentY
            })
        }
    }
    
    signal updatePopupRequested(var url)
    signal defaultEmbeddedDriveRequested(var drive)
    
    // Forward the nextClicked signal as next() function
    // If an artifact is selected but not yet inspected, inspect it first
    function next() {
        if (root.selectedArtifactModel !== null) {
            // Artifact selected but not inspected - inspect it now
            root.inspectSelectedArtifact()
        } else {
            root.nextClicked()
        }
    }

    // Inspect the currently selected artifact (deferred download)
    function inspectSelectedArtifact() {
        var model = root.selectedArtifactModel
        if (!model) return

        console.log("Inspecting artifact:", model.artifact_id, model.name)
        root.pendingArtifactModel = model
        root.selectedArtifactModel = null  // Clear so we don't re-inspect

        // Show download progress dialog
        artifactDownloadProgressDialog.artifactName = model.name
        artifactDownloadProgressDialog.progress = 0
        artifactDownloadProgressDialog.indeterminate = true
        artifactDownloadProgressDialog.open()

        // Request artifact inspection - this will download and scan the ZIP
        var repoManager = imageWriter.getRepositoryManager()
        repoManager.inspectArtifact(
            model.artifact_id,
            model.name,
            model.source_owner,
            model.source_repo,
            typeof(model.branch) !== "undefined" ? model.branch : ""
        )
    }
    
    // Common handler functions for OS selection
    function handleOSSelection(modelData, fromKeyboard, fromMouse) {
        if (fromKeyboard === undefined) {
            fromKeyboard = true  // Default to keyboard since this is called from keyboard handlers
        }
        if (fromMouse === undefined) {
            fromMouse = false  // Default to not from mouse
        }
        
        // Check if this is a sublist item - if so, navigate to it
        if (modelData && root.isOSsublist(modelData)) {
            root.selectOSitem(modelData, true, fromMouse)
        } else if (modelData && typeof(modelData.subitems_url) === "string" && modelData.subitems_url === "internal://back") {
            // Back button - just navigate back without auto-advancing
            root.selectOSitem(modelData, false, fromMouse)
        } else {
            // Regular OS selection
            root.selectOSitem(modelData, false, fromMouse)
            
            // For keyboard selection of concrete OS items, automatically advance to next step
            if (fromKeyboard && modelData && !root.isOSsublist(modelData)) {
                // Use Qt.callLater to ensure the OS selection completes first
                Qt.callLater(function() {
                    if (root.nextButtonEnabled) {
                        root.next()
                    }
                })
            }
        }
    }
    
    function handleOSNavigation(modelData) {
        // Right arrow key: only navigate to sublists, ignore regular OS items
        if (modelData && root.isOSsublist(modelData)) {
            root.selectOSitem(modelData, true, false)
        }
    }
    
    function handleBackNavigation() {
        osswipeview.decrementCurrentIndex()
        root.categorySelected = ""
        // Rebuild focus order when returning to main list
        root.rebuildFocusOrder()
    }

    
    function initializeListViewFocus(listView) {
        // No-op: Do not auto-select first item to avoid unwanted highlighting on load
    }

    Component.onCompleted: {
        // Try initial load in case data is already available
        onOsListPreparedHandler()

        // Register the OS list for keyboard navigation
        root.registerFocusGroup("os_list", function(){
            // Only include the currently active list view
            var currentPage = osswipeview.itemAt(osswipeview.currentIndex)
            return currentPage ? [currentPage] : [oslist]
        }, 0)

        // Initial focus will automatically go to title, then subtitle, then first control (handled by WizardStepBase)
        _focusFirstItemInCurrentView()
    }

    Connections {
        target: imageWriter
        function onOsListPrepared() {
            // If we were showing offline state and now have data, force full reload
            // (softRefresh only updates existing rows, doesn't add new ones)
            if (root.osListUnavailable) {
                // Still unavailable - no point refreshing
                return
            }
            
            // If model was loaded with just Erase/Use custom (2 items) but now we have more,
            // we need a full reload, not just softRefresh
            var needsFullReload = !root.modelLoaded || (root.osmodel && root.osmodel.rowCount() <= 2)
            
            if (needsFullReload) {
                root.modelLoaded = false  // Reset so handler does full reload
                onOsListPreparedHandler()
            } else if (root.osmodel && typeof root.osmodel.softRefresh === "function") {
                // Just updating existing data (e.g., sublist loaded)
                root.osmodel.softRefresh()
            }
        }
        function onOsListUnavailableChanged() {
            // When transitioning from unavailable to available, force a full reload
            if (!root.osListUnavailable && root.osmodel) {
                root.modelLoaded = false
                onOsListPreparedHandler()
            }
        }
        function onHwFilterChanged() {
            // Hardware filter changed (device selected) - reload OS list to apply new filter
            if (root.modelLoaded && root.osmodel) {
                root.osmodel.reload()
            }
        }
        // Handle native file selection for "Use custom"
        function onFileSelected(fileUrl) {
            // Ensure ImageWriter src is set to the chosen file explicitly
            imageWriter.setSrc(fileUrl)
            // Update selected OS name to the chosen file name
            root.wizardContainer.selectedOsName = imageWriter.srcFileName()
            root.wizardContainer.customizationSupported = false  // Disabled for Laerdal SimServer Imager
            // For custom images, customization is not supported; clear any staged flags
            if (!root.wizardContainer.customizationSupported) {
                root.wizardContainer.hostnameConfigured = false
                root.wizardContainer.localeConfigured = false
                root.wizardContainer.userConfigured = false
                root.wizardContainer.wifiConfigured = false
                root.wizardContainer.sshEnabled = false
                root.wizardContainer.piConnectEnabled = false
                root.wizardContainer.piConnectAvailable = false
                root.wizardContainer.secureBootAvailable = imageWriter.isSecureBootForcedByCliFlag()
            }
            root.customSelected = true
            root.customSelectedSize = imageWriter.getSelectedSourceSize()
            root.nextButtonEnabled = true
            
            // Scroll back to the "Use custom" option so user can see their selection
            Qt.callLater(function() {
                if (oslist && oslist.model) {
                    // Find the "Use custom" item (url === "internal://custom")
                    for (var i = 0; i < oslist.count; i++) {
                        var itemData = oslist.getModelData(i)
                        if (itemData && itemData.url === "internal://custom") {
                            oslist.currentIndex = i
                            oslist.positionViewAtIndex(i, ListView.Center)
                            break
                        }
                    }
                }
            })
        }
    }

    // Fallback custom FileDialog (styled) when native dialogs are unavailable
    // Exposed via property alias for callsite access
    property alias customImageFileDialog: customImageFileDialog
    ImFileDialog {
        id: customImageFileDialog
        imageWriter: root.imageWriter
        parent: root.wizardContainer && root.wizardContainer.overlayRootRef ? root.wizardContainer.overlayRootRef : (root.Window.window ? root.Window.window.overlayRootItem : null)
        anchors.centerIn: parent
        nameFilters: CommonStrings.imageFiltersList
        onAccepted: {
            imageWriter.acceptCustomImageFromQml(selectedFile)
        }
        onRejected: {
            // No-op; user cancelled
        }
    }
    
    // No-op (previous auto-focus/auto-select logic removed to avoid stealing click timing)
    function _focusFirstItemInCurrentView() {}

    // Dialog for selecting a specific file from a multi-file CI artifact
    ArtifactFileSelectionDialog {
        id: artifactFileSelectionDialog
        imageWriter: root.imageWriter
        parent: root.wizardContainer && root.wizardContainer.overlayRootRef ? root.wizardContainer.overlayRootRef : (root.Window.window ? root.Window.window.overlayRootItem : null)
        anchors.centerIn: parent

        onFileSelected: function(filename, displayName, size, fileType) {
            // User selected a specific file from the artifact
            console.log("User selected file from artifact:", filename, "display:", displayName, "type:", fileType, "cached ZIP:", artifactFileSelectionDialog.zipPath)

            if (fileType === "spu") {
                // SPU file selected - set up SPU copy mode and navigate to SPU copy step
                imageWriter.setSrcSpuArtifact(
                    artifactFileSelectionDialog.artifactId,
                    artifactFileSelectionDialog.owner,
                    artifactFileSelectionDialog.repo,
                    artifactFileSelectionDialog.branch,
                    filename,
                    artifactFileSelectionDialog.zipPath
                )

                // Update UI state for SPU mode
                root.wizardContainer.selectedSpuName = displayName
                root.wizardContainer.isSpuCopyMode = true
                root.wizardContainer.customizationSupported = false
                root.wizardContainer.piConnectAvailable = false
                root.wizardContainer.secureBootAvailable = false
                root.wizardContainer.ccRpiAvailable = false
                root.wizardContainer.ifAndFeaturesAvailable = false
                root.customSelected = false
                root.nextButtonEnabled = true
            } else {
                // WIC file selected - normal disk image flow
                imageWriter.setSrcArtifactWithTargetAndCache(
                    artifactFileSelectionDialog.artifactId,
                    artifactFileSelectionDialog.owner,
                    artifactFileSelectionDialog.repo,
                    artifactFileSelectionDialog.branch,
                    size,
                    displayName,
                    filename,
                    artifactFileSelectionDialog.zipPath  // Pass the cached ZIP path
                )

                // Update UI state
                root.wizardContainer.selectedOsName = displayName
                root.wizardContainer.isSpuCopyMode = false
                root.wizardContainer.customizationSupported = false
                root.wizardContainer.piConnectAvailable = false
                root.wizardContainer.secureBootAvailable = imageWriter.isSecureBootForcedByCliFlag()
                root.wizardContainer.ccRpiAvailable = false
                root.wizardContainer.ifAndFeaturesAvailable = false
                root.customSelected = false
                root.nextButtonEnabled = true
            }

            // Auto-advance to next step after file selection
            Qt.callLater(function() {
                if (root.nextButtonEnabled) {
                    root.nextClicked()
                }
            })
        }

        onCancelled: {
            // User cancelled file selection
            root.nextButtonEnabled = false
        }
    }

    // Pending artifact selection data (stored while waiting for inspection)
    property var pendingArtifactModel: null

    // Selected artifact that hasn't been inspected yet (for deferred download on double-click/Next)
    property var selectedArtifactModel: null

    // Download progress dialog for artifact inspection
    ArtifactDownloadProgressDialog {
        id: artifactDownloadProgressDialog
        imageWriter: root.imageWriter
        parent: root.wizardContainer && root.wizardContainer.overlayRootRef ? root.wizardContainer.overlayRootRef : (root.Window.window ? root.Window.window.contentItem : null)

        onCancelled: {
            // Cancel the download in progress
            var repoManager = imageWriter.getRepositoryManager()
            if (repoManager) {
                repoManager.cancelArtifactInspection()
            }
            root.pendingArtifactModel = null
            root.nextButtonEnabled = false
        }
    }

    // Connection to handle artifact contents ready signal
    Connections {
        target: imageWriter.getRepositoryManager()

        function onArtifactDownloadProgress(bytesReceived, bytesTotal) {
            if (bytesTotal > 0) {
                artifactDownloadProgressDialog.indeterminate = false
                artifactDownloadProgressDialog.progress = bytesReceived / bytesTotal
            } else {
                artifactDownloadProgressDialog.indeterminate = true
            }
        }

        function onArtifactContentsReady(artifactId, artifactName, owner, repo, branch, imageFiles, zipPath) {
            console.log("Artifact contents ready:", artifactId, "files:", imageFiles.length)

            // Close the progress dialog
            artifactDownloadProgressDialog.close()

            if (imageFiles.length === 0) {
                // No image files found in artifact
                root.wizardContainer.showError(qsTr("No installable images found in the CI build artifact."))
                root.nextButtonEnabled = false
            } else if (imageFiles.length === 1) {
                // Only one file - select it directly using the cached ZIP
                var file = imageFiles[0]
                var displayName = file.display_name || file.filename
                var fileType = file.type || "wic"

                if (fileType === "spu") {
                    // SPU file - set up SPU copy mode
                    imageWriter.setSrcSpuArtifact(artifactId, owner, repo, branch, file.filename, zipPath)
                    root.wizardContainer.selectedSpuName = displayName
                    root.wizardContainer.isSpuCopyMode = true
                    root.wizardContainer.customizationSupported = false
                    root.wizardContainer.piConnectAvailable = false
                    root.wizardContainer.secureBootAvailable = false
                    root.wizardContainer.ccRpiAvailable = false
                    root.wizardContainer.ifAndFeaturesAvailable = false
                } else {
                    // WIC file - normal disk image flow
                    imageWriter.setSrcArtifactWithTargetAndCache(
                        artifactId, owner, repo, branch,
                        file.size || 0, displayName, file.filename, zipPath
                    )
                    root.wizardContainer.selectedOsName = displayName
                    root.wizardContainer.isSpuCopyMode = false
                    root.wizardContainer.customizationSupported = false
                    root.wizardContainer.piConnectAvailable = false
                    root.wizardContainer.secureBootAvailable = imageWriter.isSecureBootForcedByCliFlag()
                    root.wizardContainer.ccRpiAvailable = false
                    root.wizardContainer.ifAndFeaturesAvailable = false
                }

                root.customSelected = false
                root.nextButtonEnabled = true
            } else {
                // Multiple files - show selection dialog
                artifactFileSelectionDialog.artifactId = artifactId
                artifactFileSelectionDialog.artifactName = artifactName
                artifactFileSelectionDialog.owner = owner
                artifactFileSelectionDialog.repo = repo
                artifactFileSelectionDialog.branch = branch
                artifactFileSelectionDialog.zipPath = zipPath
                artifactFileSelectionDialog.imageFiles = imageFiles
                artifactFileSelectionDialog.open()
            }

            root.pendingArtifactModel = null
        }
    }
    
    // Ensure the clicked selection is visually highlighted in the current list view
    function _highlightMatchingEntryInCurrentView(selectedModel) {
        var currentView = osswipeview.currentItem
        if (!currentView || !currentView.model || typeof currentView.model.get !== "function") {
            return
        }
        for (var i = 0; i < currentView.count; i++) {
            var entry = currentView.model.get(i)
            if (entry && entry.name === selectedModel.name && entry.url === selectedModel.url) {
                currentView.currentIndex = i
                break
            }
        }
    }
    
    // Track whether OS list is unavailable (no data loaded)
    readonly property bool osListUnavailable: imageWriter.isOsListUnavailable

    // Track whether CI images are being fetched
    readonly property var repoManager: imageWriter.getRepositoryManager()
    readonly property bool isLoadingCIImages: repoManager ? repoManager.isLoading : false

    // Content
    content: [
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // CI images loading banner
        ImLoadingBanner {
            id: loadingBanner
            active: root.isLoadingCIImages
            text: qsTr("Loading CI images from GitHub...")
            visible: !offlineBanner.visible && !ciStatusBanner. visible && root.isLoadingCIImages
        }

        // CI images status banner (shown after loading completes)
        ImBanner {
            id: ciStatusBanner
            visible: !root.isLoadingCIImages && root.repoManager && root.repoManager.statusMessage.length > 0
            text: root.repoManager ? root.repoManager.statusMessage : ""
            // Success if images found, Info otherwise
            bannerType: root.repoManager && root.repoManager.statusMessage.indexOf("found") >= 0 &&
                        root.repoManager.statusMessage.indexOf("No") < 0
                        ? ImBanner.Type.Success : ImBanner.Type.Info
        }

        // Offline banner (shown when OS list fetch failed)
        ImBanner {
            id: offlineBanner
            visible: root.osListUnavailable
            bannerType: ImBanner.Type.Warning
            text: qsTr("Unable to download OS list. You can still use a local image file.")

            ImButton {
                id: retryButton
                text: qsTr("Retry")
                accessibleDescription: qsTr("Retry downloading the OS list")
                onClicked: {
                    imageWriter.beginOSListFetch()
                }
            }
        }
        
        // OS selection area - fill available space without extra chrome/padding
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            // OS SwipeView for navigation between categories
            SwipeView {
                id: osswipeview
                anchors.fill: parent
                interactive: false
                clip: true
                focus: false  // Don't let SwipeView steal focus from its children
                activeFocusOnTab: false

                onCurrentIndexChanged: {
                    _focusFirstItemInCurrentView()
                    // Rebuild focus order when switching between main list and sublists
                    root.rebuildFocusOrder()
                    // Ensure the current view gets focus when SwipeView index changes
                    Qt.callLater(function() {
                        var currentView = osswipeview.currentItem
                        if (currentView && typeof currentView.forceActiveFocus === "function") {
                            currentView.forceActiveFocus()
                        }
                    })
                }
                    
                    // Main OS list
                    OSSelectionListView {
                        id: oslist
                        model: root.osmodel
                        delegate: osdelegate
                        accessibleName: {
                            var count = oslist.count
                            var name = qsTr("Operating system list")
                            
                            if (count === 0) {
                                name += ". " + qsTr("No operating systems")
                            } else if (count === 1) {
                                name += ". " + qsTr("1 operating system")
                            } else {
                                name += ". " + qsTr("%1 operating systems").arg(count)
                            }
                            
                            name += ". " + qsTr("Use arrow keys to navigate, Enter or Space to select")
                            return name
                        }
                        accessibleDescription: ""
                        
                        // Connect to our OS selection handler
                        osSelectionHandler: root.handleOSSelection
                        
                        onRightPressed: function(index, item, modelData) {
                            root.handleOSNavigation(modelData)
                        }
                        
                        Component.onCompleted: {
                            root.initializeListViewFocus(oslist)
                        }
                        
                        onCountChanged: {
                            root.initializeListViewFocus(oslist)
                        }
                    }
            }
        }
    }
    ]
    
    // OS delegate component
    Component {
        id: osdelegate

        SelectionListDelegate {
            id: delegateItem

            required property int index
            required property string name
            required property string description
            required property string icon
            required property string release_date
            required property string url
            required property string extract_sha256
            required property QtObject model
            required property double image_download_size
            required property var devices
            required property string source
            required property string source_type
            required property string branch
            required property var artifact_id
            required property string source_owner
            required property string source_repo

            // Format release_date to user's local timezone and locale format
            readonly property string formattedReleaseDate: {
                if (!release_date || release_date === "") {
                    return ""
                }
                var date = new Date(release_date)
                if (isNaN(date.getTime())) {
                    // If parsing fails, return the original string
                    return release_date
                }
                // Format to user's locale (date and time)
                return date.toLocaleDateString(Qt.locale()) + " " + date.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
            }

            // Cache status text for metadata line
            readonly property string cacheStatusText: {
                if (typeof(delegateItem.url) === "string" && delegateItem.url === "internal://custom") {
                    var sz = root.customSelected ? root.customSelectedSize : 0
                    return sz > 0 ? qsTr("Local - %1").arg(root.imageWriter.formatSize(sz)) : ""
                }
                if (!delegateItem.url) return ""
                if (typeof(delegateItem.extract_sha256) !== "undefined" &&
                    root.cacheStatusVersion >= 0 &&
                    root.imageWriter.isCached(delegateItem.url, delegateItem.extract_sha256)) {
                    return qsTr("Cached on your computer")
                }
                if (delegateItem.url.startsWith("file://")) {
                    return qsTr("Local file")
                }
                return qsTr("Online - %1 download").arg(root.imageWriter.formatSize(delegateItem.image_download_size))
            }

            // Whether to show cache status
            readonly property bool showCacheStatus: {
                return (typeof(delegateItem.url) === "string" && delegateItem.url !== "internal://custom" && delegateItem.url !== "internal://format")
                    || (typeof(delegateItem.url) === "string" && delegateItem.url === "internal://custom" && root.customSelected)
            }

            // Map model properties to SelectionListDelegate properties
            delegateIndex: delegateItem.index
            itemTitle: delegateItem.name
            itemDescription: delegateItem.description
            itemIcon: delegateItem.icon
            itemMetadata: delegateItem.showCacheStatus ? delegateItem.cacheStatusText : ""
            itemMetadata2: delegateItem.formattedReleaseDate !== "" ? qsTr("Released: %1").arg(delegateItem.formattedReleaseDate) : ""

            minimumHeight: 80

            // Custom badges using the badgeContent slot
            ImBadge {
                visible: delegateItem.source === "github"
                text: delegateItem.source_type === "artifact" ? qsTr("CI Build") : qsTr("Release")
                variant: delegateItem.source_type === "artifact" ? "purple" : "green"
                accessibleName: delegateItem.source_type === "artifact" ? qsTr("CI Build from GitHub Actions") : qsTr("GitHub Release")
            }

            ImBadge {
                id: imageTypeBadge
                visible: {
                    var urlStr = delegateItem.url ? delegateItem.url.toString().toLowerCase() : ""
                    return urlStr.length > 0 &&
                           !urlStr.startsWith("internal://") &&
                           (urlStr.endsWith(".spu") || urlStr.endsWith(".vsi") ||
                            urlStr.endsWith(".wic") || urlStr.endsWith(".wic.xz") ||
                            urlStr.endsWith(".wic.gz") || urlStr.endsWith(".wic.bz2") ||
                            urlStr.endsWith(".wic.zst"))
                }
                text: {
                    var urlStr = delegateItem.url ? delegateItem.url.toString().toLowerCase() : ""
                    if (urlStr.endsWith(".spu")) return qsTr("SPU")
                    if (urlStr.endsWith(".vsi")) return qsTr("VSI")
                    return qsTr("WIC")
                }
                variant: {
                    var urlStr = delegateItem.url ? delegateItem.url.toString().toLowerCase() : ""
                    if (urlStr.endsWith(".spu")) return "indigo"
                    if (urlStr.endsWith(".vsi")) return "cyan"
                    return "emerald"
                }
                accessibleName: {
                    var urlStr = delegateItem.url ? delegateItem.url.toString().toLowerCase() : ""
                    if (urlStr.endsWith(".spu")) return qsTr("Software Package Update file")
                    if (urlStr.endsWith(".vsi")) return qsTr("Versioned Sparse Image file")
                    return qsTr("Disk image file")
                }
            }
        }
    }
    
    // Sublist page component
    Component {
        id: suboslist
        
        OSSelectionListView {
            id: sublistview
            model: ListModel {
                id: sublistModel
                
                // Notify accessibility system when the model changes
                onCountChanged: {
                    // Force accessibility update by briefly toggling and restoring focus
                    if (sublistview.activeFocus) {
                        Qt.callLater(function() {
                            // The accessibleName binding will re-evaluate with the new count
                            // Force the screen reader to re-announce by resetting focus
                            var parent = sublistview.parent
                            if (parent) {
                                parent.forceActiveFocus()
                                Qt.callLater(function() {
                                    sublistview.forceActiveFocus()
                                })
                            }
                        })
                    }
                }
            }
            delegate: osdelegate
            accessibleName: {
                // Subtract 1 from count because the first item is the "Back" button, not an OS
                var osCount = Math.max(0, sublistview.count - 1)
                var name = qsTr("Operating system category")
                
                if (osCount === 0) {
                    name += ". " + qsTr("No operating systems")
                } else if (osCount === 1) {
                    name += ". " + qsTr("1 operating system")
                } else {
                    name += ". " + qsTr("%1 operating systems").arg(osCount)
                }
                
                name += ". " + qsTr("Use arrow keys to navigate, Enter or Space to select, Left arrow to go back")
                return name
            }
            accessibleDescription: ""
            
            // Connect to our OS selection handler
            osSelectionHandler: root.handleOSSelection
            
            onRightPressed: function(index, item, modelData) {
                root.handleOSNavigation(modelData)
            }
            
            onLeftPressed: {
                console.log("Sublist onLeftPressed handler called")
                root.handleBackNavigation()
            }
            
            Component.onCompleted: {
                // Build the back entry dynamically to support translations
                sublistModel.append({
                    url: "",
                    icon: "../icons/ic_chevron_left_40px.svg",
                    extract_size: 0,
                    image_download_size: 0,
                    extract_sha256: "",
                    contains_multiple_files: false,
                    release_date: "",
                    subitems_url: "internal://back",
                    subitems_json: "",
                    name: CommonStrings.back,
                    description: qsTr("Go back to main menu"),
                    tooltip: "",
                    website: "",
                    init_format: "",
                    capabilities: "",
                    devices: [],
                    source: "",
                    source_type: "",
                    branch: "",
                    artifact_id: 0,
                    source_owner: "",
                    source_repo: ""
                })
                
                // Ensure this sublist can receive keyboard focus
                forceActiveFocus()
                root.initializeListViewFocus(sublistview)
            }
        }
    }

    // OS selection functions (adapted from OSPopup.qml)
    function selectOSitem(model, navigateOnly, fromMouse) {
        if (navigateOnly === undefined) {
            navigateOnly = false
        }
        if (fromMouse === undefined) {
            fromMouse = false
        }
        
        if (isOSsublist(model)) {
            // Navigate to sublist (whether navigateOnly is true or false)
            categorySelected = model.name
            var lm = newSublist()
            populateSublistInto(lm, model)
            // Navigate to sublist
            var nextView = osswipeview.itemAt(osswipeview.currentIndex+1)
            osswipeview.incrementCurrentIndex()
            // Ensure focus is on the new view and select first item for navigation consistency
            _focusFirstItemInCurrentView()
            Qt.callLater(function() {
                var currentView = osswipeview.currentItem
                if (currentView) {
                    // Set currentIndex to 0 for sublists - user explicitly navigated here
                    currentView.currentIndex = 0
                    if (typeof currentView.forceActiveFocus === "function") {
                        currentView.forceActiveFocus()
                    }
                }
            })
        } else if (typeof(model.subitems_url) === "string" && model.subitems_url === "internal://back") {
            // Back button - just navigate back without setting any OS selection
            osswipeview.decrementCurrentIndex()
            categorySelected = ""
        } else {
            // Select this OS - explicit branching for clarity
            if (typeof(model.url) === "string" && model.url === "internal://custom") {
                // Use custom: open native file selector if available, otherwise fall back to QML FileDialog
                // Don't clear selectedOsName or customSelected here - only update them when user actually selects a file
                // Changing these properties causes delegate height changes and scroll position resets
                root.nextButtonEnabled = false
                if (imageWriter.nativeFileDialogAvailable()) {
                    // Defer opening the native dialog until after the current event completes
                    Qt.callLater(function() {
                        imageWriter.openFileDialog(
                            qsTr("Select image"),
                            CommonStrings.imageFiltersString)
                    })
                } else if (root.hasOwnProperty("customImageFileDialog")) {
                    // Ensure reasonable defaults
                    customImageFileDialog.dialogTitle = qsTr("Select image")
                    customImageFileDialog.nameFilters = CommonStrings.imageFiltersList
                    // Use last used folder from settings (falls back to Downloads)
                    var lastFolder = imageWriter.getLastImageFolder()
                    if (lastFolder && lastFolder.length > 0) {
                        var furl = (Qt.platform.os === "windows") ? ("file:///" + lastFolder) : ("file://" + lastFolder)
                        customImageFileDialog.currentFolder = furl
                        customImageFileDialog.folder = furl
                    }
                    customImageFileDialog.open()
                } else {
                    console.warn("OSSelectionStep: No FileDialog fallback available")
                }
            } else if (typeof(model.url) === "string" && model.url === "internal://format") {
                // Erase/format flow
                imageWriter.setSrc(
                    model.url,
                    model.image_download_size,
                    model.extract_size,
                    typeof(model.extract_sha256) != "undefined" ? model.extract_sha256 : "",
                    typeof(model.contains_multiple_files) != "undefined" ? model.contains_multiple_files : false,
                    categorySelected,
                    model.name,
                    typeof(model.init_format) != "undefined" ? model.init_format : ""
                )
                imageWriter.setSWCapabilitiesList("[]")

                root.wizardContainer.selectedOsName = model.name
                root.wizardContainer.customizationSupported = false  // Disabled for Laerdal SimServer Imager
                root.wizardContainer.piConnectAvailable = false
                root.wizardContainer.secureBootAvailable = imageWriter.isSecureBootForcedByCliFlag()
                root.wizardContainer.ccRpiAvailable = false
                root.wizardContainer.ifAndFeaturesAvailable = false
                root.nextButtonEnabled = true
                if (fromMouse) {
                    Qt.callLater(function() { _highlightMatchingEntryInCurrentView(model) })
                }
            } else {
                // Normal OS selection - check if this is a GitHub artifact
                if (typeof(model.source_type) === "string" && model.source_type === "artifact" &&
                    typeof(model.artifact_id) !== "undefined" && model.artifact_id > 0) {
                    // GitHub CI artifact - defer download until double-click or Next button
                    // Just select/highlight the item for now
                    console.log("Artifact selected (deferred download):", model.artifact_id, model.name)
                    root.selectedArtifactModel = model
                    root.wizardContainer.selectedOsName = model.name
                    root.nextButtonEnabled = true  // Enable Next so user can click it to trigger download
                    if (fromMouse) {
                        Qt.callLater(function() { _highlightMatchingEntryInCurrentView(model) })
                    }
                    return  // Exit early - inspection will happen on Next/double-click
                } else {
                    // Regular OS (CDN or GitHub release)
                    // Check if this is an SPU file based on URL extension
                    var urlLower = model.url.toString().toLowerCase()
                    var isSpu = urlLower.endsWith(".spu")

                    if (isSpu) {
                        // SPU file from CDN - set up SPU copy mode
                        console.log("SPU file selected from CDN:", model.url)
                        imageWriter.setSrcSpuUrl(model.url, model.image_download_size, model.name)

                        root.wizardContainer.selectedOsName = model.name
                        root.wizardContainer.isSpuCopyMode = true
                        root.wizardContainer.customizationSupported = false
                        root.wizardContainer.piConnectAvailable = false
                        root.wizardContainer.secureBootAvailable = false
                        root.wizardContainer.ccRpiAvailable = false
                        root.wizardContainer.ifAndFeaturesAvailable = false
                        root.customSelected = false
                        root.nextButtonEnabled = true
                        if (fromMouse) {
                            Qt.callLater(function() { _highlightMatchingEntryInCurrentView(model) })
                        }
                        return  // Early exit for SPU files
                    }

                    // Regular WIC/VSI disk image
                    imageWriter.setSrc(
                        model.url,
                        model.image_download_size,
                        model.extract_size,
                        typeof(model.extract_sha256) != "undefined" ? model.extract_sha256 : "",
                        typeof(model.contains_multiple_files) != "undefined" ? model.contains_multiple_files : false,
                        categorySelected,
                        model.name,
                        typeof(model.init_format) != "undefined" ? model.init_format : "",
                        typeof(model.release_date) != "undefined" ? model.release_date : ""
                    )
                }
                imageWriter.setSWCapabilitiesList(model.capabilities)

                root.wizardContainer.selectedOsName = model.name
                root.wizardContainer.isSpuCopyMode = false  // Explicitly set to false for WIC/VSI
                root.wizardContainer.customizationSupported = false  // Disabled for Laerdal SimServer Imager
                root.wizardContainer.piConnectAvailable = imageWriter.checkSWCapability("rpi_connect")
                root.wizardContainer.secureBootAvailable = imageWriter.checkSWCapability("secure_boot") || imageWriter.isSecureBootForcedByCliFlag()
                root.wizardContainer.ccRpiAvailable = imageWriter.imageSupportsCcRpi()

                // Check if any interface/feature capabilities are available (requires both HW and SW support)
                if (root.wizardContainer.ccRpiAvailable) {
                    var hasAnyIfFeatures = imageWriter.checkHWAndSWCapability("i2c") ||
                                           imageWriter.checkHWAndSWCapability("spi") ||
                                           imageWriter.checkHWAndSWCapability("onewire") ||
                                           imageWriter.checkHWAndSWCapability("serial") ||
                                           imageWriter.checkHWAndSWCapability("usb_otg")
                    root.wizardContainer.ifAndFeaturesAvailable = hasAnyIfFeatures
                } else {
                    root.wizardContainer.ifAndFeaturesAvailable = false
                }

                // Clean up incompatible settings from customizationSettings based on OS capabilities
                if (!root.wizardContainer.piConnectAvailable) {
                    delete root.wizardContainer.customizationSettings.piConnectEnabled
                    root.wizardContainer.piConnectEnabled = false
                }
                if (!root.wizardContainer.secureBootAvailable) {
                    delete root.wizardContainer.customizationSettings.secureBootEnabled
                    root.wizardContainer.secureBootEnabled = false
                }
                if (!root.wizardContainer.ccRpiAvailable) {
                    delete root.wizardContainer.customizationSettings.enableI2C
                    delete root.wizardContainer.customizationSettings.enableSPI
                    delete root.wizardContainer.customizationSettings.enable1Wire
                    delete root.wizardContainer.customizationSettings.enableSerial
                    delete root.wizardContainer.customizationSettings.enableUsbGadget
                    root.wizardContainer.ifI2cEnabled = false
                    root.wizardContainer.ifSpiEnabled = false
                    root.wizardContainer.if1WireEnabled = false
                    root.wizardContainer.ifSerial = "Disabled"
                    root.wizardContainer.featUsbGadgetEnabled = false
                }

                root.customSelected = false
                root.nextButtonEnabled = true
                if (fromMouse) {
                    Qt.callLater(function() { _highlightMatchingEntryInCurrentView(model) })
                }
            }
            // Stay on page; user must click Next
        }
    }
    
    function isOSsublist(model) {
        // Properly handle undefined/null values
        var jsonType = typeof(model.subitems_json)
        var jsonNotEmpty = model.subitems_json !== ""
        var hasSubitemsJson = (jsonType == "string" && jsonNotEmpty)
        
        var urlType = typeof(model.subitems_url)
        var urlNotEmpty = model.subitems_url !== ""
        var urlNotBack = model.subitems_url !== "internal://back"
        var hasSubitemsUrl = (urlType == "string" && urlNotEmpty && urlNotBack)
        
        var isSublist = hasSubitemsJson || hasSubitemsUrl
        
        return isSublist
    }
    
    // Add or reuse sublist page and return its ListModel
    function newSublist() {
        if (osswipeview.currentIndex === (osswipeview.count - 1)) {
            var newlist = suboslist.createObject(osswipeview)
            osswipeview.addItem(newlist)
            // Rebuild focus order to include the new sublist
            root.rebuildFocusOrder()
        }
        var m = osswipeview.itemAt(osswipeview.currentIndex+1).model
        if (m.count > 1) {
            m.remove(1, m.count - 1)
        }
        return m
    }

    // Populate given ListModel from a model's subitems_json, flattening nested items
    function populateSublistInto(listModel, model) {
        if (typeof(model.subitems_json) !== "string" || model.subitems_json === "") {
            return
        }
        var subitems = []
        try {
            subitems = JSON.parse(model.subitems_json)
        } catch (e) {
            console.log("Failed to parse subitems_json:", e)
            return
        }
        for (var i in subitems) {
            var entry = subitems[i]
            if (entry && typeof(entry) === "object") {
                if ("subitems" in entry) {
                    entry["subitems_json"] = JSON.stringify(entry["subitems"])
                    delete entry["subitems"]
                }
                // Propagate init_format from parent when missing so customization remains available
                if (typeof(entry.init_format) === "undefined" && typeof(model.init_format) === "string" && model.init_format !== "") {
                    entry.init_format = model.init_format
                }
                if (typeof(entry.icon) === "string" && entry.icon.indexOf("icons/") === 0) {
                    entry.icon = "../" + entry.icon
                }
                // Ensure role types remain consistent across the ListModel
                entry.url = String(entry.url || "")
                entry.icon = String(entry.icon || "")
                entry.subitems_url = String(entry.subitems_url || "")
                entry.website = String(entry.website || "")

                if (typeof entry.capabilities === "string") {
                    // keep it
                } else if (Array.isArray(entry.capabilities)) {
                    entry.capabilities = JSON.stringify(entry.capabilities);
                } else if (entry.capabilities && typeof entry.capabilities.length === "number") {
                    // QVariantList-looking object
                    entry.capabilities = JSON.stringify(Array.prototype.slice.call(entry.capabilities));
                } else {
                    entry.capabilities = "[]";
                }

                listModel.append(entry)
            }
        }
    }
    
    // Called when OS list data is ready from network
    function onOsListPreparedHandler() {
        if (!root || !root.osmodel) {
            return
        }
        // Always reload to reflect cache status changes and updates from backend
        var osSuccess = root.osmodel.reload()
        if (osSuccess && !modelLoaded) {
            modelLoaded = true
            var o = JSON.parse(root.imageWriter.getFilteredOSlist())
            if ("imager" in o) {
                var imager = o["imager"]
                if (root.imageWriter.getBoolSetting("check_version") && "latest_version" in imager && "url" in imager) {
                    if (!root.imageWriter.isEmbeddedMode() && root.imageWriter.isVersionNewer(imager["latest_version"])) {
                        root.updatePopupRequested(imager["url"])
                    }
                }
                if ("default_os" in imager) {
                    selectNamedOS(imager["default_os"], root.osmodel)
                }
                if (root.imageWriter.isEmbeddedMode()) {
                    if ("embedded_default_os" in imager) {
                        selectNamedOS(imager["embedded_default_os"], root.osmodel)
                    }
                    if ("embedded_default_destination" in imager) {
                        root.defaultEmbeddedDriveRequested(imager["embedded_default_destination"])
                    }
                }
            }
        }
    }
    
    function selectNamedOS(osName, model) {
        for (var i = 0; i < model.rowCount(); i++) {
            var entry = model.get(i)
            if (entry && entry.name === osName) {
                selectOSitem(entry)
                break
            }
        }
    }
} 
