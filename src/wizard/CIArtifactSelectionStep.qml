/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import RpiImager

WizardStepBase {
    id: root

    required property ImageWriter imageWriter
    required property var wizardContainer

    title: {
        if (root.isDownloading) {
            return qsTr("Downloading artifact")
        }
        return qsTr("Select file from artifact")
    }
    
    subtitle: qsTr("Artifact: <b>%1</b>").arg(root.artifactName)
    showNextButton: true
    nextButtonEnabled: !root.isDownloading && root.selectedFileIndex >= 0  // Can advance if file selected and not downloading
    backButtonEnabled: true  // Always enabled - cancels download if in progress

    // Download state
    property bool isDownloading: false
    property real downloadProgress: 0
    property string artifactName: ""
    property bool downloadIndeterminate: true

    // Propagate download state to WizardContainer for close confirmation
    onIsDownloadingChanged: {
        console.log("CIArtifactSelectionStep: isDownloading changed to", isDownloading)
        root.wizardContainer.isDownloading = isDownloading
        if (isDownloading) {
            console.log("CIArtifactSelectionStep: Showing Phase 1 (download progress)")
        } else {
            console.log("CIArtifactSelectionStep: Phase 1 complete, checking for Phase 2...")
        }
    }

    onImageFilesChanged: {
        console.log("CIArtifactSelectionStep: imageFiles changed, length:", imageFiles.length)
        if (!isDownloading && imageFiles.length > 0) {
            console.log("CIArtifactSelectionStep: Showing Phase 2 (file selection)")
        }
    }

    // Download tracking
    property real bytesReceived: 0
    property real bytesTotal: 0
    property real downloadSpeedMbps: 0
    property real lastBytes: 0
    property real lastUpdateTime: 0
    property int lastLoggedMilestone: -1

    // File selection state
    property var imageFiles: []
    property int selectedFileIndex: -1
    property var artifactId: 0
    property string artifactNameForFiles: ""
    property string owner: ""
    property string repo: ""
    property string branch: ""
    property string zipPath: ""

    // Pending artifact from OSSelectionStep
    property var pendingArtifact: null

    // Track whether CI images are being fetched
    readonly property var repoManager: imageWriter.getRepositoryManager()
    readonly property bool isLoadingCIImages: repoManager ? repoManager.isLoading : false

    // Filter release assets by device - only show assets matching selected device
    // Platform-independent files (no device pattern) are shown to all devices
    function filterAssetsByDevice(assets, selectedDevice) {
        if (!assets || !selectedDevice) return assets

        return assets.filter(function(asset) {
            var name = (asset.name || "").toLowerCase()

            // Detect device from filename using same patterns as extractDeviceName()
            var fileDevice = null
            if (name.includes("simman3g-64") || name.includes("simman-64")) {
                fileDevice = "simman3g-64"
            } else if (name.includes("simman3g-32") || name.includes("simman-32")) {
                fileDevice = "simman3g-32"
            } else if (name.includes("simman3g") || name.includes("simman")) {
                fileDevice = "simman3g"
            } else if (name.includes("imx8") || name.includes("simpad2")) {
                fileDevice = "imx8"
            } else if (name.includes("imx6") || (name.includes("simpad") && !name.includes("simpad2"))) {
                fileDevice = "imx6"
            }
            // No device detected = platform-independent, show to all

            if (fileDevice === null) return true  // Generic file - always show
            return fileDevice === selectedDevice   // Device-specific - match only
        })
    }

    // Sort assets: factory-image first, then system update SPUs, then others
    function sortAssetsByPriority(assets) {
        if (!assets) return assets

        // Regex to match system update SPU files: *-X.X.X.XXX.spu (version pattern)
        var systemSpuRegex = /\d+\.\d+\.\d+\.\d+\.spu$/i

        return assets.slice().sort(function(a, b) {
            // CI artifacts use 'filename', release assets use 'name'
            var nameA = (a.filename || a.name || "").toLowerCase()
            var nameB = (b.filename || b.name || "").toLowerCase()

            // Priority: factory-image = 0, system SPU (version pattern) = 1, update = 2, others = 3
            function getPriority(name) {
                if (name.includes("factory-image")) return 0
                if (systemSpuRegex.test(name)) return 1  // System update SPU with version
                if (name.includes("update")) return 2
                return 3
            }

            var priorityA = getPriority(nameA)
            var priorityB = getPriority(nameB)

            if (priorityA !== priorityB) {
                return priorityA - priorityB
            }

            // Same priority - sort alphabetically
            return nameA.localeCompare(nameB)
        })
    }

    content: [
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
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
            // PHASE 1: DOWNLOAD PROGRESS (visible when downloading)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Style.spacingLarge
                visible: root.isDownloading

                Item { Layout.fillHeight: true }

                // Progress bar
                ImProgressBar {
                    id: downloadProgressBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Layout.maximumWidth: Style.sectionMaxWidth
                    Layout.alignment: Qt.AlignHCenter
                    value: root.downloadProgress
                    from: 0
                    to: 1
                    indeterminate: root.downloadIndeterminate
                    showText: true
                    indeterminateText: qsTr("Connecting...")
                }

                // Progress details
                Text {
                    //visible: !root.downloadIndeterminate
                    text: {
                        var parts = []
                        if (root.bytesTotal > 0) {
                            parts.push(Utils.formatBytes(root.bytesReceived) + " / " +
                                      Utils.formatBytes(root.bytesTotal))
                        }
                        if (root.downloadSpeedMbps > 0) {
                            parts.push(Math.round(root.downloadSpeedMbps) + " Mbps")
                            // Calculate and display time remaining
                            var timeRemaining = Utils.calculateTimeRemainingMbps(
                                root.bytesReceived, root.bytesTotal, root.downloadSpeedMbps)
                            var timeStr = Utils.formatTimeRemaining(timeRemaining)
                            if (timeStr !== "") {
                                parts.push(timeStr)
                            }
                        }
                        return parts.join("  •  ")
                    }
                    font.pixelSize: Style.fontSizeDescription
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Item { Layout.fillHeight: true }
            }

            // PHASE 2: FILE SELECTION (visible when download complete)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Style.spacingMedium
                visible: !root.isDownloading && root.imageFiles.length > 0

                // File list
                SelectionListView {
                    id: fileListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    model: root.imageFiles

                    // Handle item selection
                    onItemSelected: function(index, item) {
                        root.selectedFileIndex = index
                    }

                    // Handle double-click to auto-advance
                    onItemDoubleClicked: function(index, item) {
                        root.selectedFileIndex = index
                        root.nextClicked()
                    }

                    delegate: SelectionListDelegate {
                        id: fileDelegate
                        required property int index
                        required property var modelData

                        delegateIndex: fileDelegate.index
                        itemTitle: fileDelegate.modelData.display_name || fileDelegate.modelData.filename || fileDelegate.modelData.name
                        itemDescription: Utils.formatBytes(fileDelegate.modelData.size || 0)
                        isItemSelected: root.selectedFileIndex === fileDelegate.index

                        badges: {
                            var badgeList = []
                            var fileType = fileDelegate.modelData.type || "wic"
                            // ImBadge automatically sets text/variant/accessible from type
                            badgeList.push({type: fileType})
                            return badgeList
                        }
                    }
                }
            }
        }
    ]

    // Start download when step appears (or restore state if returning via back navigation)
    Component.onCompleted: {
        // Cache validation logic:
        // 1. If pendingArtifactInspection is null → going back from Storage, restore cache
        // 2. If pendingArtifactInspection exists and matches cache → same artifact, restore cache
        // 3. If pendingArtifactInspection exists but doesn't match → different artifact, reject cache
        console.log("CIArtifactSelectionStep: Component.onCompleted - checking state")
        console.log("  Initial isDownloading:", root.isDownloading)
        console.log("  Initial imageFiles.length:", root.imageFiles.length)
        console.log("  cachedArtifactFiles.length:", root.wizardContainer.cachedArtifactFiles.length)
        console.log("  pendingArtifactInspection:", root.wizardContainer.pendingArtifactInspection ? "exists" : "null")
        console.log("  pendingReleaseInspection:", root.wizardContainer.pendingReleaseInspection ? "exists" : "null")
        if (root.wizardContainer.pendingArtifactInspection) {
            console.log("  pendingArtifactInspection.artifact_id:", root.wizardContainer.pendingArtifactInspection.artifact_id)
            console.log("  pendingArtifactInspection.name:", root.wizardContainer.pendingArtifactInspection.name)
        }
        if (root.wizardContainer.pendingReleaseInspection) {
            console.log("  pendingReleaseInspection.name:", root.wizardContainer.pendingReleaseInspection.name)
        }
        console.log("  cachedArtifactId:", root.wizardContainer.cachedArtifactId)

        var hasCache = root.wizardContainer.cachedArtifactFiles.length > 0
        var hasPending = root.wizardContainer.pendingArtifactInspection !== null
        var idsMatch = hasPending && (root.wizardContainer.cachedArtifactId === root.wizardContainer.pendingArtifactInspection.artifact_id)

        // Restore cache if:
        // - We have cache AND no pending (going back from Storage)
        // - We have cache AND pending matches (same artifact selected again)
        var shouldRestoreCache = hasCache && (!hasPending || idsMatch)

        console.log("  hasCache:", hasCache, "hasPending:", hasPending, "idsMatch:", idsMatch, "shouldRestoreCache:", shouldRestoreCache)

        if (shouldRestoreCache) {
            console.log("CIArtifactSelectionStep: Cache validation PASSED - restoring cached artifact state with", root.wizardContainer.cachedArtifactFiles.length, "files")

            // Restore all cached state
            root.imageFiles = root.wizardContainer.cachedArtifactFiles
            root.artifactId = root.wizardContainer.cachedArtifactId
            root.artifactNameForFiles = root.wizardContainer.cachedArtifactName
            root.owner = root.wizardContainer.cachedArtifactOwner
            root.repo = root.wizardContainer.cachedArtifactRepo
            root.branch = root.wizardContainer.cachedArtifactBranch
            root.zipPath = root.wizardContainer.cachedArtifactZipPath
            root.artifactName = root.wizardContainer.cachedArtifactName
            root.selectedFileIndex = root.wizardContainer.cachedSelectedFileIndex

            // Ensure download state is fully cleared (defensive)
            root.isDownloading = false
            root.downloadIndeterminate = false
            root.downloadProgress = 0
            root.wizardContainer.isDownloading = false  // Clear container state too

            console.log("CIArtifactSelectionStep: Restored selected file index:", root.selectedFileIndex)
            console.log("CIArtifactSelectionStep: imageFiles.length after restore:", root.imageFiles.length)

            // Sync ListView's currentIndex with selectedFileIndex to ensure consistent highlighting
            // This prevents multiple highlight colors from appearing
            Qt.callLater(function() {
                fileListView.currentIndex = root.selectedFileIndex
                console.log("CIArtifactSelectionStep: Synced ListView currentIndex to", root.selectedFileIndex)
            })
            return
        }

        // Check for pending release inspection (release assets are already available)
        var hasPendingRelease = root.wizardContainer.pendingReleaseInspection !== null

        if (hasPendingRelease) {
            console.log("CIArtifactSelectionStep: Loading release assets (no download needed)")
            var release = root.wizardContainer.pendingReleaseInspection
            root.artifactName = release.name
            root.owner = release.owner
            root.repo = release.repo
            root.branch = release.tag  // Use tag as "branch" for display
            root.artifactId = 0  // No artifact ID for releases
            root.isDownloading = false

            // Get selected device tag for filtering
            var hwFilterList = root.imageWriter.getHWFilterList()
            var selectedDevice = (hwFilterList && hwFilterList.length > 0) ? hwFilterList[0] : ""
            console.log("CIArtifactSelectionStep: Filtering release assets by device:", selectedDevice)

            var filteredAssets = root.filterAssetsByDevice(release.assets, selectedDevice)
            console.log("CIArtifactSelectionStep: Filtered", release.assets.length, "assets to", filteredAssets.length)

            // Sort: factory images first, then update images, then others
            var sortedAssets = root.sortAssetsByPriority(filteredAssets)
            root.imageFiles = sortedAssets

            // Cache results for back navigation (release assets use artifactId = 0)
            root.wizardContainer.cachedArtifactFiles = sortedAssets
            root.wizardContainer.cachedArtifactId = 0  // Release assets have no artifact ID
            root.wizardContainer.cachedArtifactName = release.name
            root.wizardContainer.cachedArtifactOwner = release.owner
            root.wizardContainer.cachedArtifactRepo = release.repo
            root.wizardContainer.cachedArtifactBranch = release.tag
            root.wizardContainer.cachedArtifactZipPath = ""  // No zip for releases
            console.log("CIArtifactSelectionStep: Cached release asset state for back navigation")

            // Clear pending release
            root.wizardContainer.pendingReleaseInspection = null

            // If only one asset matches, auto-select and proceed
            if (filteredAssets.length === 1) {
                console.log("CIArtifactSelectionStep: Only one matching asset, auto-selecting")
                root.selectedFileIndex = 0
                Qt.callLater(function() {
                    root.nextClicked()
                })
            }
            return
        }

        // Otherwise, start new artifact inspection (different artifact or first visit)
        if (hasPending) {
            console.log("CIArtifactSelectionStep: Starting new artifact inspection")
            var artifact = root.wizardContainer.pendingArtifactInspection
            root.pendingArtifact = artifact
            root.artifactName = artifact.name
            root.isDownloading = true
            root.downloadIndeterminate = true
            root.lastLoggedMilestone = -1

            console.log("CIArtifactSelectionStep: Inspecting artifact:", artifact.name, "ID:", artifact.artifact_id)

            // Start artifact inspection
            var repoManager = root.imageWriter.getRepositoryManager()
            repoManager.inspectArtifact(
                artifact.artifact_id,
                artifact.name,
                artifact.source_owner,
                artifact.source_repo,
                artifact.branch || ""
            )
        } else if (!hasCache) {
            console.log("CIArtifactSelectionStep: ERROR - No pending artifact and no cache!")
        } else {
            console.log("CIArtifactSelectionStep: ERROR - Unexpected state: has cache but shouldn't restore?")
        }
    }

    // Monitor download progress
    Connections {
        target: root.imageWriter.getRepositoryManager()

        function onArtifactDownloadProgress(bytesReceived, bytesTotal) {
            if (!root.isDownloading) return

            root.bytesReceived = bytesReceived
            root.bytesTotal = bytesTotal

            if (bytesTotal > 0) {
                root.downloadIndeterminate = false
                root.downloadProgress = bytesReceived / bytesTotal

                var result = Utils.calculateThroughputMbps(
                    bytesReceived, root.lastBytes, root.lastUpdateTime,
                    root.downloadSpeedMbps, 500, 0.3
                )
                if (result !== null) {
                    root.downloadSpeedMbps = result.throughputMbps
                    root.lastBytes = result.newLastBytes
                    root.lastUpdateTime = result.newLastTime

                    // Log progress every 10% milestone (once per milestone)
                    var milestone = Math.floor(root.downloadProgress * 10) * 10
                    if (milestone > root.lastLoggedMilestone) {
                        root.lastLoggedMilestone = milestone
                        console.log("CIArtifactSelectionStep: Download progress:",
                                   milestone + "%",
                                   Utils.formatBytes(bytesReceived), "/", Utils.formatBytes(bytesTotal),
                                   Math.round(root.downloadSpeedMbps), "Mbps")
                    }
                }
            }
        }

        function onArtifactContentsReady(artifactId, artifactName, owner, repo, branch, imageFiles, zipPath) {
            console.log("CIArtifactSelectionStep: Artifact contents ready -", artifactName)
            console.log("CIArtifactSelectionStep: Number of files found:", imageFiles.length)

            root.isDownloading = false

            if (imageFiles.length === 0) {
                console.log("CIArtifactSelectionStep: No files found - showing error")
                root.wizardContainer.showError(
                    qsTr("No installable images found"),
                    qsTr("The CI build artifact does not contain any installable image files.")
                )
                Qt.callLater(function() {
                    root.wizardContainer.previousStep()
                })
            } else if (imageFiles.length === 1) {
                // Single file - configure and advance
                var file = imageFiles[0]
                var displayName = file.display_name || file.filename
                var fileType = file.type || "wic"

                console.log("CIArtifactSelectionStep: Single file found -", displayName, "(" + fileType + ")")
                console.log("CIArtifactSelectionStep: Auto-advancing to storage")

                if (fileType === "spu") {
                    root.imageWriter.setSrcSpuArtifact(artifactId, owner, repo, branch, file.filename, zipPath)
                    root.wizardContainer.selectedSpuName = displayName
                    root.wizardContainer.isSpuCopyMode = true
                    root.wizardContainer.customizationSupported = false
                    root.wizardContainer.piConnectAvailable = false
                    root.wizardContainer.secureBootAvailable = false
                } else {
                    root.imageWriter.setSrcArtifactWithTargetAndCache(
                        artifactId, owner, repo, branch,
                        file.size || 0, displayName, file.filename, zipPath
                    )
                    root.wizardContainer.selectedOsName = displayName
                    root.wizardContainer.isSpuCopyMode = false
                    root.wizardContainer.customizationSupported = false
                    root.wizardContainer.piConnectAvailable = false
                    root.wizardContainer.secureBootAvailable = root.imageWriter.isSecureBootForcedByCliFlag()
                }

                // Auto-advance to storage
                Qt.callLater(function() {
                    root.wizardContainer.nextStep()
                })
            } else {
                // Multiple files - show inline file selection
                console.log("CIArtifactSelectionStep: Multiple files found - showing file selection")
                for (var i = 0; i < imageFiles.length; i++) {
                    console.log("  File", i + ":", imageFiles[i].display_name || imageFiles[i].filename,
                               "(" + (imageFiles[i].type || "wic") + ")",
                               Utils.formatBytes(imageFiles[i].size || 0))
                }

                // Sort: factory-image first, then system SPUs, then others
                root.imageFiles = root.sortAssetsByPriority(imageFiles)
                root.artifactId = artifactId
                root.artifactNameForFiles = artifactName
                root.owner = owner
                root.repo = repo
                root.branch = branch
                root.zipPath = zipPath

                // Cache results for back navigation
                root.wizardContainer.cachedArtifactFiles = imageFiles
                root.wizardContainer.cachedArtifactId = artifactId
                root.wizardContainer.cachedArtifactName = artifactName
                root.wizardContainer.cachedArtifactOwner = owner
                root.wizardContainer.cachedArtifactRepo = repo
                root.wizardContainer.cachedArtifactBranch = branch
                root.wizardContainer.cachedArtifactZipPath = zipPath
                console.log("CIArtifactSelectionStep: Cached artifact state for back navigation")

                // Subtitle will update to "Select an image file..."
            }

            // Clear pending
            root.wizardContainer.pendingArtifactInspection = null
        }

        function onRefreshError(message) {
            if (!root.isDownloading) return
            console.log("CIArtifactSelectionStep: Download error:", message)
            root.isDownloading = false
            root.wizardContainer.pendingArtifactInspection = null
            root.wizardContainer.showError(qsTr("Artifact download failed"), message)
            Qt.callLater(function() {
                root.wizardContainer.previousStep()
            })
        }
    }

    // Back button handler - cancel download if in progress
    onBackClicked: {
        if (root.isDownloading) {
            // Cancel download in progress
            console.log("CIArtifactSelectionStep: User cancelled download via Back button - going back to OS selection")
            var repoManager = root.imageWriter.getRepositoryManager()
            if (repoManager) {
                repoManager.cancelArtifactInspection()
            }
            root.isDownloading = false
            // Clear pending artifact to ensure clean state
            root.wizardContainer.pendingArtifactInspection = null
        }
        // Go back to OS selection (both when cancelling download and normal back navigation)
        root.wizardContainer.previousStep()
    }

    // Next button handler - advance to storage with selected file
    onNextClicked: {
        if (root.selectedFileIndex >= 0) {
            // File selected - configure and advance
            var file = root.imageFiles[root.selectedFileIndex]
            var displayName = file.display_name || file.filename || file.name
            var fileType = file.type || "wic"

            // Check if this is a release asset (has asset_id and download_url)
            // vs a CI artifact file (needs artifact streaming from ZIP)
            var isReleaseAsset = typeof(file.asset_id) !== "undefined" && file.asset_id > 0

            if (isReleaseAsset) {
                // Release asset - use direct URL download with authentication
                console.log("CIArtifactSelectionStep: Configuring release asset download:", displayName)

                if (fileType === "spu") {
                    root.imageWriter.setSrcSpuUrl(file.download_url, file.size || 0, displayName)
                    // Set release asset info for authenticated download
                    root.imageWriter.setGitHubReleaseAsset(file.asset_id, root.owner, root.repo)
                    root.wizardContainer.selectedSpuName = displayName
                    root.wizardContainer.isSpuCopyMode = true
                    root.wizardContainer.customizationSupported = false
                    root.wizardContainer.piConnectAvailable = false
                    root.wizardContainer.secureBootAvailable = false
                } else {
                    root.imageWriter.setSrc(
                        file.download_url,
                        file.size || 0,
                        file.size || 0,  // extract_size (assume same as download for now)
                        "",  // sha256
                        false,  // not multiple files
                        "",  // category
                        displayName,
                        "",  // init_format
                        ""   // release_date
                    )
                    // Set release asset info for authenticated download
                    root.imageWriter.setGitHubReleaseAsset(file.asset_id, root.owner, root.repo)
                    root.wizardContainer.selectedOsName = displayName
                    root.wizardContainer.isSpuCopyMode = false
                    root.wizardContainer.customizationSupported = false
                    root.wizardContainer.piConnectAvailable = false
                    root.wizardContainer.secureBootAvailable = root.imageWriter.isSecureBootForcedByCliFlag()
                }
            } else {
                // CI artifact file - use artifact streaming from ZIP
                if (fileType === "spu") {
                    root.imageWriter.setSrcSpuArtifact(
                        root.artifactId, root.owner, root.repo, root.branch,
                        file.filename, root.zipPath
                    )
                    root.wizardContainer.selectedSpuName = displayName
                    root.wizardContainer.isSpuCopyMode = true
                    root.wizardContainer.customizationSupported = false
                    root.wizardContainer.piConnectAvailable = false
                    root.wizardContainer.secureBootAvailable = false
                } else {
                    root.imageWriter.setSrcArtifactWithTargetAndCache(
                        root.artifactId, root.owner, root.repo, root.branch,
                        file.size || 0, displayName, file.filename, root.zipPath
                    )
                    root.wizardContainer.selectedOsName = displayName
                    root.wizardContainer.isSpuCopyMode = false
                    root.wizardContainer.customizationSupported = false
                    root.wizardContainer.piConnectAvailable = false
                    root.wizardContainer.secureBootAvailable = root.imageWriter.isSecureBootForcedByCliFlag()
                }
            }

            // Cache selected file index for back navigation
            root.wizardContainer.cachedSelectedFileIndex = root.selectedFileIndex

            // Advance to storage
            Qt.callLater(function() {
                root.wizardContainer.nextStep()
            })
        }
    }
}
