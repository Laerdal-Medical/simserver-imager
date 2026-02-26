/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import RpiImager

WizardStepBase {
    id: root

    required property ImageWriter imageWriter
    required property var wizardContainer

    title: qsTr("Select download source")
    subtitle: qsTr("Choose where to download images from")
    showNextButton: true
    nextButtonEnabled: true

    // Fetch images when navigating to next step with a GitHub source selected
    onNextClicked: {
        if ((root.selectedSourceType === "github-releases" || root.selectedSourceType === "github-ci") && root.repoManager) {
            console.log("SourceSelectionStep: GitHub source selected, fetching images before proceeding...")
            root.repoManager.refreshAllSources()
        }
    }

    // Properties for repository manager access
    property var repoManager: imageWriter ? imageWriter.getRepositoryManager() : null
    property var githubAuth: imageWriter ? imageWriter.getGitHubAuth() : null
    property bool isGitHubAuthenticated: githubAuth ? githubAuth.isAuthenticated : false
    property bool hasGitHubRepos: repoManager ? repoManager.githubRepos.length > 0 : false
    property bool isGitHubAvailable: isGitHubAuthenticated && hasGitHubRepos

    // Source type: "cdn" or "github"
    property string selectedSourceType: repoManager ? repoManager.selectedSourceType : "cdn"

    // Button group for radio buttons to make them mutually exclusive
    ButtonGroup {
        id: sourceTypeButtonGroup
        buttons: [cdnRadio, githubReleasesRadio, githubCIRadio]
    }

    // Listen for GitHub auth changes
    Connections {
        target: root.githubAuth
        enabled: root.githubAuth !== null
        function onAuthenticationChanged() {
            root.isGitHubAuthenticated = root.githubAuth.isAuthenticated
        }
    }

    // Environment options
    readonly property var environmentOptions: [
        { value: 0, label: qsTr("Production"), description: qsTr("Stable releases for production use") },
        { value: 1, label: qsTr("Test"), description: qsTr("Test builds for QA validation") },
        { value: 2, label: qsTr("Development"), description: qsTr("Development builds (unstable)") },
        { value: 3, label: qsTr("Beta"), description: qsTr("Beta releases for early testing") },
        { value: 4, label: qsTr("Release Candidate"), description: qsTr("Release candidates for final validation") }
    ]

    property int selectedEnvironment: repoManager ? repoManager.currentEnvironment : 0

    Component.onCompleted: {
        // Register focus groups for keyboard navigation
        root.registerFocusGroup("source_type_section", function(){
            return [cdnRadio, githubReleasesRadio, githubCIRadio]
        }, 0)

        root.registerFocusGroup("environment_section", function(){
            return [environmentCombo]
        }, 1)

        root.registerFocusGroup("branch_filter_section", function(){
            var items = []
            if (branchFilterCombo.visible) items.push(branchFilterCombo)
            return items
        }, 2)
    }

    // Update environment when combo changes
    onSelectedEnvironmentChanged: {
        if (repoManager) {
            repoManager.currentEnvironment = selectedEnvironment
        }
    }

    // Update source type in repo manager
    onSelectedSourceTypeChanged: {
        if (repoManager) {
            repoManager.selectedSourceType = selectedSourceType
        }
    }

    // Content
    content: [
    Flickable {
        id: sourceFlickable
        anchors.fill: parent
        contentWidth: parent.width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // Touch scrolling improvements
        flickDeceleration: 1500  // Slower deceleration for smoother touch scrolling
        maximumFlickVelocity: 2500  // Reasonable max velocity
        pressDelay: 50  // Brief delay to distinguish tap from scroll on touch

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: Style.spacingLarge

            // Source Type Selection
            WizardSectionContainer {
                Layout.fillWidth: true

                WizardFormLabel {
                    text: qsTr("Image Source")
                    Layout.fillWidth: true
                }

                WizardDescriptionText {
                    text: qsTr("Choose where to download images from.")
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingSmall

                    // CDN Radio Option
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall

                        ImRadioButton {
                            id: cdnRadio
                            checked: root.selectedSourceType === "cdn"

                            onCheckedChanged: {
                                if (checked) {
                                    root.selectedSourceType = "cdn"
                                }
                            }

                            accessibleDescription: qsTr("Download images from Laerdal CDN")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingXXSmall

                            Text {
                                text: qsTr("Laerdal CDN")
                                font.pixelSize: Style.fontSizeFormLabel
                                font.family: Style.fontFamilyBold
                                font.bold: true
                                color: Style.formLabelColor

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: cdnRadio.checked = true
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }

                            Text {
                                text: qsTr("Official release images from Laerdal's content delivery network")
                                font.pixelSize: Style.fontSizeCaption
                                font.family: Style.fontFamily
                                color: Style.textDescriptionColor

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: cdnRadio.checked = true
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }
                        }
                    }

                    // GitHub Releases Radio Option
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall

                        ImRadioButton {
                            id: githubReleasesRadio
                            checked: root.selectedSourceType === "github-releases"
                            enabled: root.isGitHubAvailable

                            onCheckedChanged: {
                                if (checked) {
                                    root.selectedSourceType = "github-releases"
                                }
                            }

                            accessibleDescription: root.isGitHubAvailable
                                                    ? qsTr("Download images from GitHub releases")
                                                    : (!root.isGitHubAuthenticated
                                                       ? qsTr("Sign in to GitHub to enable this option")
                                                       : qsTr("No GitHub repositories configured"))
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingXXSmall

                            Text {
                                text: qsTr("GitHub Releases")
                                font.pixelSize: Style.fontSizeFormLabel
                                font.family: Style.fontFamilyBold
                                font.bold: true
                                color: githubReleasesRadio.enabled ? Style.formLabelColor : Style.formLabelDisabledColor

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: githubReleasesRadio.enabled
                                    onClicked: githubReleasesRadio.checked = true
                                    cursorShape: githubReleasesRadio.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                            }

                            Text {
                                text: root.isGitHubAvailable
                                      ? qsTr("Release candidates published on GitHub")
                                      : (!root.isGitHubAuthenticated
                                         ? qsTr("Sign in to GitHub in App Options to enable")
                                         : qsTr("No GitHub repositories configured"))
                                font.pixelSize: Style.fontSizeCaption
                                font.family: Style.fontFamily
                                color: githubReleasesRadio.enabled ? Style.textDescriptionColor : Style.formLabelDisabledColor

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: githubReleasesRadio.enabled
                                    onClicked: githubReleasesRadio.checked = true
                                    cursorShape: githubReleasesRadio.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                            }
                        }
                    }

                    // GitHub CI Artifacts Radio Option
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall

                        ImRadioButton {
                            id: githubCIRadio
                            checked: root.selectedSourceType === "github-ci"
                            enabled: root.isGitHubAvailable

                            onCheckedChanged: {
                                if (checked) {
                                    root.selectedSourceType = "github-ci"
                                }
                            }

                            accessibleDescription: root.isGitHubAvailable
                                                    ? qsTr("Download images from GitHub CI artifacts")
                                                    : (!root.isGitHubAuthenticated
                                                       ? qsTr("Sign in to GitHub to enable this option")
                                                       : qsTr("No GitHub repositories configured"))
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingXXSmall

                            Text {
                                text: qsTr("GitHub CI Artifacts")
                                font.pixelSize: Style.fontSizeFormLabel
                                font.family: Style.fontFamilyBold
                                font.bold: true
                                color: githubCIRadio.enabled ? Style.formLabelColor : Style.formLabelDisabledColor

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: githubCIRadio.enabled
                                    onClicked: githubCIRadio.checked = true
                                    cursorShape: githubCIRadio.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                            }

                            Text {
                                text: root.isGitHubAvailable
                                      ? qsTr("Development builds from GitHub Actions CI pipelines")
                                      : (!root.isGitHubAuthenticated
                                         ? qsTr("Sign in to GitHub in App Options to enable")
                                         : qsTr("No GitHub repositories configured"))
                                font.pixelSize: Style.fontSizeCaption
                                font.family: Style.fontFamily
                                color: githubCIRadio.enabled ? Style.textDescriptionColor : Style.formLabelDisabledColor

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: githubCIRadio.enabled
                                    onClicked: githubCIRadio.checked = true
                                    cursorShape: githubCIRadio.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                            }
                        }
                    }
                }
            }

            // CDN Environment Selection Section (visible when CDN is selected)
            WizardSectionContainer {
                Layout.fillWidth: true
                visible: root.selectedSourceType === "cdn"

                WizardFormLabel {
                    text: qsTr("CDN Environment")
                    Layout.fillWidth: true
                }

                WizardDescriptionText {
                    text: qsTr("Select which environment to download official Laerdal images from.")
                    Layout.fillWidth: true
                }

                ComboBox {
                    id: environmentCombo
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.buttonHeightStandard
                    model: root.environmentOptions
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.selectedEnvironment

                    onCurrentIndexChanged: {
                        root.selectedEnvironment = currentIndex
                    }

                    delegate: ItemDelegate {
                        id: envDelegate
                        required property var modelData
                        required property int index

                        width: environmentCombo.width
                        height: envDelegateColumn.implicitHeight + Style.spacingSmall * 2

                        contentItem: ColumnLayout {
                            id: envDelegateColumn
                            spacing: Style.spacingXXSmall

                            Text {
                                text: envDelegate.modelData.label
                                font.pixelSize: Style.fontSizeFormLabel
                                font.family: Style.fontFamilyBold
                                font.bold: true
                                color: Style.formLabelColor
                            }

                            Text {
                                text: envDelegate.modelData.description
                                font.pixelSize: Style.fontSizeCaption
                                font.family: Style.fontFamily
                                color: Style.textDescriptionColor
                            }
                        }

                        highlighted: environmentCombo.highlightedIndex === envDelegate.index
                    }

                    Accessible.role: Accessible.ComboBox
                    Accessible.name: qsTr("Environment selector")
                    Accessible.description: qsTr("Select the Laerdal CDN environment for downloading images")
                }
            }

            // GitHub Artifact Branch Filter Section (visible when GitHub is selected)
            WizardSectionContainer {
                Layout.fillWidth: true
                visible: root.selectedSourceType === "github-ci" && root.isGitHubAvailable

                WizardFormLabel {
                    text: qsTr("Branch Filter")
                    Layout.fillWidth: true
                }

                WizardDescriptionText {
                    text: qsTr("Filter CI build artifacts by branch. Only artifacts from the selected branch will be shown.")
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingSmall

                    ImComboBox {
                        id: branchFilterCombo
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.buttonHeightStandard

                        // Make editable so user can type to filter and see their input
                        editable: true

                        // Select all text when field gains focus for easy re-editing
                        onActiveFocusChanged: {
                            if (activeFocus && contentItem) {
                                contentItem.selectAll()
                            }
                        }

                        // Use a stable internal copy of branches to avoid model updates while popup is open
                        // This prevents focus loss during typing when branches are being fetched
                        property var availableBranches: []
                        property var pendingBranches: root.repoManager ? root.repoManager.availableBranches : []

                        // Track the user's selected branch name (not index) to preserve across model updates
                        property string selectedBranchName: root.repoManager ? root.repoManager.artifactBranchFilter : ""

                        // Update availableBranches only when popup is closed to preserve focus
                        // Also update currentIndex to match the selected branch in the new list
                        onPendingBranchesChanged: {
                            if (!popup.visible) {
                                availableBranches = pendingBranches
                                syncCurrentIndexToSelectedBranch()
                            }
                        }

                        // Also update when popup closes if there are pending changes
                        Connections {
                            target: branchFilterCombo.popup
                            function onVisibleChanged() {
                                if (!branchFilterCombo.popup.visible &&
                                    branchFilterCombo.pendingBranches !== branchFilterCombo.availableBranches) {
                                    branchFilterCombo.availableBranches = branchFilterCombo.pendingBranches
                                    branchFilterCombo.syncCurrentIndexToSelectedBranch()
                                }
                            }
                        }

                        // Sync currentIndex to match selectedBranchName in the current model
                        function syncCurrentIndexToSelectedBranch() {
                            if (!selectedBranchName || selectedBranchName === "") {
                                currentIndex = 0  // "Default branch"
                                return
                            }
                            var branches = availableBranches
                            for (var i = 0; i < branches.length; i++) {
                                if (branches[i] === selectedBranchName) {
                                    currentIndex = i + 1  // +1 because "Default branch" is at index 0
                                    return
                                }
                            }
                            // Branch not found in list - keep showing the selected branch name
                            // but set index to 0 as fallback
                            currentIndex = 0
                        }

                        model: {
                            // "Default branch" shows CI artifacts from repo default branch
                            // Other branches show CI artifacts from that specific branch
                            var branches = [qsTr("Default branch")].concat(availableBranches)
                            return branches
                        }

                        // Don't use a binding for currentIndex - we manage it imperatively
                        // to prevent it from being reset when the model changes
                        currentIndex: 0

                        // Track the popup highlight during filtering, separate from
                        // currentIndex to avoid overwriting editText while typing
                        property int _matchedIndex: -1
                        property bool _filtering: false

                        // Handle text input for filtering - find and highlight matching branch
                        onEditTextChanged: {
                            if (_filtering) return
                            if (!editText || editText.trim() === "") {
                                _matchedIndex = -1
                                return
                            }
                            _filtering = true
                            var searchText = editText.trim().toLowerCase()
                            var branches = model

                            // Find first matching branch (case-insensitive prefix match)
                            for (var i = 0; i < branches.length; i++) {
                                if (branches[i].toLowerCase().startsWith(searchText)) {
                                    _matchedIndex = i
                                    // Only update popup highlight - don't set currentIndex
                                    // (setting currentIndex overwrites editText in editable combos)
                                    if (popup.visible && popup.contentItem) {
                                        popup.contentItem.currentIndex = i
                                        popup.contentItem.positionViewAtIndex(i, ListView.Center)
                                    }
                                    _filtering = false
                                    return
                                }
                            }

                            // No prefix match - try contains match
                            for (var j = 0; j < branches.length; j++) {
                                if (branches[j].toLowerCase().indexOf(searchText) >= 0) {
                                    _matchedIndex = j
                                    if (popup.visible && popup.contentItem) {
                                        popup.contentItem.currentIndex = j
                                        popup.contentItem.positionViewAtIndex(j, ListView.Center)
                                    }
                                    _filtering = false
                                    return
                                }
                            }

                            // No match found
                            _matchedIndex = -1
                            _filtering = false
                        }

                        function applyFilterAndAdvance() {
                            // Use _matchedIndex from typing, fall back to currentIndex
                            // (which ImComboBox sets from the popup highlight on Enter)
                            var selectedIndex = _matchedIndex >= 0 ? _matchedIndex : currentIndex
                            console.log("applyFilterAndAdvance: _matchedIndex =", _matchedIndex,
                                        "currentIndex =", currentIndex, "selectedIndex =", selectedIndex)

                            if (root.repoManager && selectedIndex >= 0 && selectedIndex < model.length) {
                                if (selectedIndex === 0) {
                                    selectedBranchName = ""
                                    root.repoManager.setArtifactBranchFilter("")
                                } else {
                                    selectedBranchName = availableBranches[selectedIndex - 1]
                                    root.repoManager.setArtifactBranchFilter(selectedBranchName)
                                }
                                currentIndex = selectedIndex
                            }
                            _matchedIndex = -1
                            root.nextClicked()
                        }

                        // Connect to text field's accepted signal in onCompleted
                        // to ensure contentItem is fully initialized
                        Component.onCompleted: {
                            availableBranches = pendingBranches
                            syncCurrentIndexToSelectedBranch()
                            if (contentItem && contentItem.accepted) {
                                contentItem.accepted.connect(applyFilterAndAdvance)
                            }
                        }

                        onActivated: function(index) {
                            if (root.repoManager) {
                                if (index === 0) {
                                    // "Default branch" - show CI artifacts from default branch
                                    selectedBranchName = ""
                                    root.repoManager.setArtifactBranchFilter("")
                                } else {
                                    // Specific branch - show only CI artifacts from that branch
                                    selectedBranchName = availableBranches[index - 1]
                                    root.repoManager.setArtifactBranchFilter(selectedBranchName)
                                }
                            }
                        }

                        Accessible.role: Accessible.ComboBox
                        Accessible.name: qsTr("Branch filter")
                        Accessible.description: qsTr("Select which branch to fetch GitHub artifacts from, or type to filter.")
                    }

                    // Refresh button to manually re-fetch branches
                    ImButton {
                        id: refreshBranchesButton
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: Style.buttonHeightStandard

                        text: qsTr("Refresh")

                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Refresh the list of available branches from GitHub")
                        ToolTip.delay: 500

                        onClicked: {
                            if (root.repoManager) {
                                console.log("SourceSelectionStep: Manual branch refresh requested")
                                root.repoManager.fetchAvailableBranches()
                            }
                        }

                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Refresh branches")
                        Accessible.description: qsTr("Click to refresh the list of available branches from GitHub")
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
