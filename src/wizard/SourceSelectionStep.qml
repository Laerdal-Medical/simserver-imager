/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../qmlcomponents"

import RpiImager

WizardStepBase {
    id: root

    required property ImageWriter imageWriter
    required property var wizardContainer

    title: qsTr("Select download source")
    subtitle: qsTr("Choose where to download images from")
    showNextButton: true
    nextButtonEnabled: true

    // Properties for repository manager access
    property var repoManager: imageWriter ? imageWriter.getRepositoryManager() : null
    property var githubAuth: imageWriter ? imageWriter.getGitHubAuth() : null
    property bool isGitHubAuthenticated: githubAuth ? githubAuth.isAuthenticated : false

    // Listen for GitHub auth changes
    Connections {
        target: root.githubAuth
        enabled: root.githubAuth !== null
        function onAuthenticationChanged() {
            root.isGitHubAuthenticated = root.githubAuth.isAuthenticated
        }
    }

    // Listen for available branches updates from repo manager
    Connections {
        target: root.repoManager
        enabled: root.repoManager !== null
        function onAvailableBranchesChanged() {
            // Refresh the branch filter when branches are ready
            if (root.repoManager) {
                branchFilterCombo.availableBranches = root.repoManager.availableBranches
            }
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
        root.registerFocusGroup("environment_section", function(){
            return [environmentCombo]
        }, 0)

        root.registerFocusGroup("branch_filter_section", function(){
            var items = []
            if (branchFilterCombo.visible) items.push(branchFilterCombo)
            return items
        }, 1)
    }

    // Update environment when combo changes
    onSelectedEnvironmentChanged: {
        if (repoManager) {
            repoManager.currentEnvironment = selectedEnvironment
        }
    }

    // Content
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

            // Environment Selection Section
            WizardSectionContainer {
                Layout.fillWidth: true

                WizardFormLabel {
                    text: qsTr("Laerdal CDN Environment")
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

            // GitHub Artifact Branch Filter Section (visible when authenticated)
            WizardSectionContainer {
                Layout.fillWidth: true
                visible: root.isGitHubAuthenticated

                WizardFormLabel {
                    text: qsTr("GitHub Artifact Branch Filter")
                    Layout.fillWidth: true
                }

                WizardDescriptionText {
                    text: qsTr("Filter CI build artifacts by branch. Only artifacts from the selected branch will be shown in the image list.")
                    Layout.fillWidth: true
                }

                ComboBox {
                    id: branchFilterCombo
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.buttonHeightStandard

                    property var availableBranches: root.repoManager ? root.repoManager.availableBranches : []
                    property string currentFilter: root.repoManager ? root.repoManager.artifactBranchFilter : ""

                    model: {
                        var branches = [""].concat(availableBranches)
                        return branches
                    }

                    displayText: currentIndex === 0 ? qsTr("Default branches") : currentText

                    currentIndex: {
                        if (!currentFilter || currentFilter === "") return 0
                        var branches = availableBranches
                        for (var i = 0; i < branches.length; i++) {
                            if (branches[i] === currentFilter) return i + 1
                        }
                        return 0
                    }

                    onActivated: function(index) {
                        if (root.repoManager) {
                            if (index === 0) {
                                root.repoManager.setArtifactBranchFilter("")
                            } else {
                                root.repoManager.setArtifactBranchFilter(availableBranches[index - 1])
                            }
                        }
                    }

                    delegate: ItemDelegate {
                        id: branchDelegate
                        required property string modelData
                        required property int index

                        width: branchFilterCombo.width
                        height: Style.buttonHeightStandard

                        contentItem: Text {
                            text: branchDelegate.index === 0 ? qsTr("Default branches") : branchDelegate.modelData
                            font.pixelSize: Style.fontSizeFormLabel
                            font.family: Style.fontFamily
                            color: Style.formLabelColor
                            verticalAlignment: Text.AlignVCenter
                        }

                        highlighted: branchFilterCombo.highlightedIndex === branchDelegate.index
                    }

                    Accessible.role: Accessible.ComboBox
                    Accessible.name: qsTr("Branch filter")
                    Accessible.description: qsTr("Select which branch to fetch GitHub artifacts from")
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
