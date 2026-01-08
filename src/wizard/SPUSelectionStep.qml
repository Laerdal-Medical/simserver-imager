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

    required property ImageWriter imageWriter
    required property var wizardContainer

    // Properties for repository manager and GitHub access
    property var repoManager: imageWriter ? imageWriter.getRepositoryManager() : null
    property var githubAuth: imageWriter ? imageWriter.getGitHubAuth() : null
    property bool isGitHubAuthenticated: githubAuth ? githubAuth.isAuthenticated : false

    // SPU selection state
    property var selectedSpuFile: null
    property string selectedSpuZipPath: ""
    property bool isLoadingArtifacts: false
    property var inspectedSpuFiles: []  // SPU files found in the inspected artifact
    property var pendingArtifactModel: null  // Artifact being inspected
    property int downloadProgress: 0

    title: qsTr("Select SPU File")
    subtitle: qsTr("Choose a firmware update file to copy to USB")
    showNextButton: true
    nextButtonEnabled: selectedSpuFile !== null

    // CDN SPU files from OS list (direct .spu URLs)
    property var cdnSpuFiles: {
        var files = []
        if (repoManager) {
            var osListJson = imageWriter.getFilteredOSlistDocument()
            if (osListJson && osListJson.object && osListJson.object.os_list) {
                for (var i = 0; i < osListJson.object.os_list.length; i++) {
                    var item = osListJson.object.os_list[i]
                    if (item.url && item.url.toString().toLowerCase().endsWith(".spu")) {
                        files.push({
                            name: item.name || "",
                            description: item.description || "",
                            url: item.url,
                            size: item.image_download_size || 0,
                            source: "cdn",
                            source_type: "cdn"
                        })
                    }
                }
            }
        }
        return files
    }

    // GitHub CI artifacts from OS list (need inspection for SPU files)
    property var ciArtifacts: {
        var artifacts = []
        if (repoManager) {
            var osListJson = imageWriter.getFilteredOSlistDocument()
            if (osListJson && osListJson.object && osListJson.object.os_list) {
                for (var i = 0; i < osListJson.object.os_list.length; i++) {
                    var item = osListJson.object.os_list[i]
                    if (item.source_type === "artifact" && item.artifact_id) {
                        artifacts.push({
                            name: item.name || "CI Artifact",
                            description: item.description || "",
                            artifact_id: item.artifact_id,
                            source_owner: item.source_owner || "",
                            source_repo: item.source_repo || "",
                            branch: item.branch || "",
                            source: "github",
                            source_type: "artifact"
                        })
                    }
                }
            }
        }
        return artifacts
    }

    // Combined list: CDN SPU files + CI artifacts (to inspect) + inspected SPU files
    property var displayList: {
        var items = []

        // Add CDN SPU files directly (they can be selected immediately)
        for (var i = 0; i < cdnSpuFiles.length; i++) {
            items.push(cdnSpuFiles[i])
        }

        // Add inspected SPU files from GitHub artifacts
        for (var j = 0; j < inspectedSpuFiles.length; j++) {
            items.push(inspectedSpuFiles[j])
        }

        // Add CI artifacts that haven't been inspected yet
        for (var k = 0; k < ciArtifacts.length; k++) {
            // Only show if we're authenticated and no SPU files have been loaded from this artifact
            if (root.isGitHubAuthenticated && inspectedSpuFiles.length === 0) {
                items.push(ciArtifacts[k])
            }
        }

        return items
    }

    // Listen for SPU artifact inspection results from RepositoryManager
    Connections {
        target: root.repoManager
        enabled: root.repoManager !== null

        function onArtifactSpuContentsReady(artifactId, artifactName, owner, repo, branch, spuFiles, zipPath) {
            console.log("SPUSelectionStep: Received SPU contents for artifact", artifactName, "- found", spuFiles.length, "SPU files")
            artifactDownloadDialog.close()
            root.isLoadingArtifacts = false

            if (spuFiles.length === 0) {
                // No SPU files in this artifact
                noSpuFilesDialog.artifactName = artifactName
                noSpuFilesDialog.open()
                return
            }

            // Convert to array and add metadata
            var files = []
            for (var i = 0; i < spuFiles.length; i++) {
                var file = spuFiles[i]
                files.push({
                    name: file.filename || file.display_name || "Unknown",
                    description: qsTr("From artifact: %1 (Branch: %2)").arg(artifactName).arg(branch),
                    filename: file.filename,
                    size: file.size || 0,
                    artifactId: artifactId,
                    artifactName: artifactName,
                    owner: owner,
                    repo: repo,
                    branch: branch,
                    zipPath: zipPath,
                    source: "github",
                    source_type: "spu_file"
                })
            }
            root.inspectedSpuFiles = files

            // If only one SPU file, auto-select it
            if (files.length === 1) {
                root.selectSpuFile(files[0])
            }
        }

        function onArtifactDownloadProgress(bytesReceived, bytesTotal) {
            if (bytesTotal > 0) {
                root.downloadProgress = Math.round((bytesReceived * 100) / bytesTotal)
            }
        }

        function onArtifactInspectionCancelled() {
            console.log("SPUSelectionStep: Artifact inspection cancelled")
            artifactDownloadDialog.close()
            root.isLoadingArtifacts = false
        }

        function onRefreshError(message) {
            console.log("SPUSelectionStep: Error:", message)
            artifactDownloadDialog.close()
            root.isLoadingArtifacts = false
        }
    }

    Component.onCompleted: {
        // Register focus groups for keyboard navigation
        root.registerFocusGroup("spu_list", function(){
            return [spuListView]
        }, 0)
    }

    function inspectArtifact(artifact) {
        if (!root.repoManager) return

        console.log("SPUSelectionStep: Inspecting artifact for SPU files:", artifact.name)
        root.isLoadingArtifacts = true
        root.downloadProgress = 0
        root.pendingArtifactModel = artifact

        // Show download progress dialog
        artifactDownloadDialog.artifactName = artifact.name
        artifactDownloadDialog.open()

        // Request artifact inspection
        root.repoManager.inspectSpuArtifact(
            artifact.artifact_id,
            artifact.name,
            artifact.source_owner,
            artifact.source_repo,
            artifact.branch
        )
    }

    function selectSpuFile(spuFile) {
        root.selectedSpuFile = spuFile
        if (spuFile && spuFile.zipPath) {
            root.selectedSpuZipPath = spuFile.zipPath
        }

        console.log("SPUSelectionStep: Selected SPU file:", spuFile ? spuFile.name : "none")

        // Set the SPU source in ImageWriter
        if (spuFile) {
            if (spuFile.source === "github" && spuFile.source_type === "spu_file") {
                // SPU file from inspected GitHub artifact
                imageWriter.setSrcSpuArtifact(
                    spuFile.artifactId,
                    spuFile.owner,
                    spuFile.repo,
                    spuFile.branch,
                    spuFile.filename,
                    spuFile.zipPath
                )
            } else if (spuFile.source === "cdn" && spuFile.url) {
                // CDN SPU file - set URL source (will be downloaded during copy)
                console.log("SPUSelectionStep: CDN SPU file selected:", spuFile.url)
                imageWriter.setSrcSpuUrl(spuFile.url, spuFile.size || 0, spuFile.name || "")
            }
        }
    }

    function handleItemClicked(item) {
        if (item.source_type === "artifact") {
            // This is a CI artifact - inspect it for SPU files
            root.inspectArtifact(item)
        } else {
            // This is a direct SPU file (CDN or from inspected artifact)
            root.selectSpuFile(item)
        }
    }

    // Artifact download progress dialog
    BaseDialog {
        id: artifactDownloadDialog
        property string artifactName: ""

        title: qsTr("Downloading Artifact")
        implicitWidth: 400

        ColumnLayout {
            spacing: Style.spacingMedium
            width: parent.width

            Text {
                text: qsTr("Downloading and scanning artifact for SPU files...")
                font.pixelSize: Style.fontSizeFormLabel
                font.family: Style.fontFamily
                color: Style.formLabelColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Text {
                text: artifactDownloadDialog.artifactName
                font.pixelSize: Style.fontSizeCaption
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            ProgressBar {
                from: 0
                to: 100
                value: root.downloadProgress
                Layout.fillWidth: true
            }

            Text {
                text: root.downloadProgress + "%"
                font.pixelSize: Style.fontSizeCaption
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
                Layout.alignment: Qt.AlignHCenter
            }

            ImButton {
                text: qsTr("Cancel")
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    root.repoManager.cancelArtifactInspection()
                    artifactDownloadDialog.close()
                }
            }
        }
    }

    // No SPU files found dialog
    BaseDialog {
        id: noSpuFilesDialog
        property string artifactName: ""

        title: qsTr("No SPU Files Found")
        implicitWidth: 400

        ColumnLayout {
            spacing: Style.spacingMedium
            width: parent.width

            Text {
                text: qsTr("No SPU files (.spu) were found in this artifact.")
                font.pixelSize: Style.fontSizeFormLabel
                font.family: Style.fontFamily
                color: Style.formLabelColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Text {
                text: noSpuFilesDialog.artifactName
                font.pixelSize: Style.fontSizeCaption
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            ImButton {
                text: qsTr("OK")
                Layout.alignment: Qt.AlignHCenter
                onClicked: noSpuFilesDialog.close()
            }
        }
    }

    content: [
        Flickable {
            anchors.fill: parent
            contentWidth: parent.width
            contentHeight: contentColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                width: Style.scrollBarWidth
                policy: ScrollBar.AsNeeded
            }

            ColumnLayout {
                id: contentColumn
                width: parent.width - Style.scrollBarWidth
                spacing: Style.spacingLarge

                // Loading indicator
                WizardSectionContainer {
                    Layout.fillWidth: true
                    visible: root.isLoadingArtifacts

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingMedium

                        BusyIndicator {
                            running: root.isLoadingArtifacts
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                        }

                        Text {
                            text: qsTr("Loading SPU files...")
                            font.pixelSize: Style.fontSizeFormLabel
                            font.family: Style.fontFamily
                            color: Style.textDescriptionColor
                        }
                    }
                }

                // Empty state
                WizardSectionContainer {
                    Layout.fillWidth: true
                    visible: !root.isLoadingArtifacts && root.displayList.length === 0

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingMedium

                        Text {
                            text: qsTr("No SPU Files Available")
                            font.pixelSize: Style.fontSizeFormLabel
                            font.family: Style.fontFamilyBold
                            font.bold: true
                            color: Style.formLabelColor
                            Layout.fillWidth: true
                        }

                        Text {
                            text: root.isGitHubAuthenticated
                                ? qsTr("No SPU files were found in the CDN or GitHub CI artifacts. Make sure your CI builds produce .spu files.")
                                : qsTr("No SPU files found in CDN. Sign in to GitHub in Settings to access CI artifacts.")
                            font.pixelSize: Style.fontSizeCaption
                            font.family: Style.fontFamily
                            color: Style.textDescriptionColor
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }

                // SPU file / artifact list
                WizardSectionContainer {
                    Layout.fillWidth: true
                    visible: !root.isLoadingArtifacts && root.displayList.length > 0

                    WizardFormLabel {
                        text: qsTr("Available SPU Files")
                        Layout.fillWidth: true
                    }

                    Text {
                        text: qsTr("Select an SPU file to copy, or click on a CI artifact to scan it for SPU files.")
                        font.pixelSize: Style.fontSizeCaption
                        font.family: Style.fontFamily
                        color: Style.textDescriptionColor
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        visible: root.ciArtifacts.length > 0 && root.inspectedSpuFiles.length === 0
                    }

                    ListView {
                        id: spuListView
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 400)
                        model: root.displayList
                        clip: true
                        spacing: Style.spacingSmall
                        currentIndex: -1

                        delegate: ItemDelegate {
                            id: spuDelegate
                            required property var modelData
                            required property int index

                            width: spuListView.width
                            height: spuDelegateContent.implicitHeight + Style.spacingSmall * 2
                            highlighted: spuListView.currentIndex === index

                            property bool isSelected: root.selectedSpuFile === modelData
                            property bool isArtifact: modelData.source_type === "artifact"

                            background: Rectangle {
                                color: spuDelegate.isSelected ? Style.laerdalBlue
                                     : spuDelegate.highlighted ? Style.listViewHoverRowBackgroundColor
                                     : Style.listViewRowBackgroundColor
                                radius: Style.listItemBorderRadius
                                border.color: spuDelegate.isSelected ? Style.laerdalBlue
                                            : spuDelegate.isArtifact ? Style.textDescriptionColor
                                            : "transparent"
                                border.width: spuDelegate.isArtifact ? 1 : 2
                            }

                            contentItem: ColumnLayout {
                                id: spuDelegateContent
                                spacing: Style.spacingXXSmall

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.spacingSmall

                                    // Icon for artifact vs SPU file
                                    Text {
                                        text: spuDelegate.isArtifact ? "📦" : "📄"
                                        font.pixelSize: Style.fontSizeFormLabel
                                        visible: true
                                    }

                                    Text {
                                        text: spuDelegate.modelData.name || "Unknown"
                                        font.pixelSize: Style.fontSizeFormLabel
                                        font.family: Style.fontFamilyBold
                                        font.bold: true
                                        color: spuDelegate.isSelected ? "white" : Style.formLabelColor
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }

                                    // Source badge
                                    Rectangle {
                                        width: sourceBadgeText.implicitWidth + Style.spacingSmall * 2
                                        height: sourceBadgeText.implicitHeight + Style.spacingXXSmall * 2
                                        radius: Style.listItemBorderRadius
                                        color: spuDelegate.modelData.source === "github" ? "#238636" : "#0969da"

                                        Text {
                                            id: sourceBadgeText
                                            anchors.centerIn: parent
                                            text: spuDelegate.isArtifact ? qsTr("CI Artifact")
                                                : spuDelegate.modelData.source === "github" ? qsTr("CI")
                                                : qsTr("CDN")
                                            font.pixelSize: Style.fontSizeCaption
                                            font.family: Style.fontFamily
                                            color: "white"
                                        }
                                    }
                                }

                                // Description or branch info
                                Text {
                                    text: {
                                        if (spuDelegate.isArtifact) {
                                            return qsTr("Click to scan for SPU files (Branch: %1)").arg(spuDelegate.modelData.branch || "unknown")
                                        } else if (spuDelegate.modelData.description) {
                                            return spuDelegate.modelData.description
                                        }
                                        return ""
                                    }
                                    font.pixelSize: Style.fontSizeCaption
                                    font.family: Style.fontFamily
                                    color: spuDelegate.isSelected ? "white" : Style.textDescriptionColor
                                    visible: text.length > 0
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                // Size info (only for actual SPU files)
                                Text {
                                    text: spuDelegate.modelData.size > 0 && !spuDelegate.isArtifact
                                        ? qsTr("Size: %1").arg(root.imageWriter.formatSize(spuDelegate.modelData.size))
                                        : ""
                                    font.pixelSize: Style.fontSizeCaption
                                    font.family: Style.fontFamily
                                    color: spuDelegate.isSelected ? "white" : Style.textDescriptionColor
                                    visible: text.length > 0
                                }
                            }

                            onClicked: {
                                spuListView.currentIndex = index
                                root.handleItemClicked(modelData)
                            }

                            Keys.onReturnPressed: function(event) {
                                spuListView.currentIndex = index
                                root.handleItemClicked(modelData)
                            }

                            Keys.onEnterPressed: function(event) {
                                spuListView.currentIndex = index
                                root.handleItemClicked(modelData)
                            }
                        }
                    }
                }

                // Spacer
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    ]
}
