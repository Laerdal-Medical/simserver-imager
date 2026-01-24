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
                        itemTitle: fileDelegate.modelData.display_name || fileDelegate.modelData.filename
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
        console.log("CIArtifactSelectionStep: Component.onCompleted - checking cache")
        console.log("  cachedArtifactFiles.length:", root.wizardContainer.cachedArtifactFiles.length)
        console.log("  pendingArtifactInspection:", root.wizardContainer.pendingArtifactInspection ? "exists" : "null")
        if (root.wizardContainer.pendingArtifactInspection) {
            console.log("  pendingArtifactInspection.artifact_id:", root.wizardContainer.pendingArtifactInspection.artifact_id)
            console.log("  pendingArtifactInspection.name:", root.wizardContainer.pendingArtifactInspection.name)
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
            root.imageFiles = root.wizardContainer.cachedArtifactFiles
            root.artifactId = root.wizardContainer.cachedArtifactId
            root.artifactNameForFiles = root.wizardContainer.cachedArtifactName
            root.owner = root.wizardContainer.cachedArtifactOwner
            root.repo = root.wizardContainer.cachedArtifactRepo
            root.branch = root.wizardContainer.cachedArtifactBranch
            root.zipPath = root.wizardContainer.cachedArtifactZipPath
            root.artifactName = root.wizardContainer.cachedArtifactName
            root.selectedFileIndex = root.wizardContainer.cachedSelectedFileIndex
            root.isDownloading = false
            console.log("CIArtifactSelectionStep: Restored selected file index:", root.selectedFileIndex)

            // Sync ListView's currentIndex with selectedFileIndex to ensure consistent highlighting
            // This prevents multiple highlight colors from appearing
            Qt.callLater(function() {
                fileListView.currentIndex = root.selectedFileIndex
                console.log("CIArtifactSelectionStep: Synced ListView currentIndex to", root.selectedFileIndex)
            })
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

                root.imageFiles = imageFiles
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
            var displayName = file.display_name || file.filename
            var fileType = file.type || "wic"

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

            // Cache selected file index for back navigation
            root.wizardContainer.cachedSelectedFileIndex = root.selectedFileIndex

            // Advance to storage
            Qt.callLater(function() {
                root.wizardContainer.nextStep()
            })
        }
    }
}
