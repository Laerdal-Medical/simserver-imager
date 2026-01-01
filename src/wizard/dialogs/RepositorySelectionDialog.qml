/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import RpiImager

BaseDialog {
    id: root

    required property var repoManager

    title: qsTr("GitHub Repositories")
    implicitWidth: 480
    // Ensure dialog is tall enough to contain all content including buttons
    // Use larger height when add form is visible
    height: root.showAddForm ? 500 : 420

    // Get repos from manager
    property var repos: repoManager ? repoManager.githubRepos : []

    // Listen for repo changes to refresh list
    Connections {
        target: root.repoManager
        function onReposChanged() {
            root.repos = root.repoManager.githubRepos
        }
    }

    // State for add repo form
    property bool showAddForm: false
    property string newRepoOwner: ""
    property string newRepoName: ""
    property string newRepoBranch: ""  // Empty = auto-detect from GitHub

    // State for editing repo branch
    property string editingRepoOwner: ""
    property string editingRepoName: ""
    property string editingRepoBranch: ""

    onOpened: {
        // Refresh repos list when dialog opens
        if (repoManager) {
            repos = repoManager.githubRepos
        }
        showAddForm = false
        newRepoOwner = ""
        newRepoName = ""
        newRepoBranch = ""
        editingRepoOwner = ""
        editingRepoName = ""
        editingRepoBranch = ""
    }

    // Content goes directly in the BaseDialog (uses default property)

    WizardDescriptionText {
        text: qsTr("Select which GitHub repositories to search for WIC images. Enable repositories to include their releases and CI builds in the image list.")
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    // Repository list
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 200
        color: Style.listViewRowBackgroundColor
        border.color: Style.titleSeparatorColor
        border.width: 1
        radius: 4

        ListView {
            id: repoListView
            anchors.fill: parent
            anchors.margins: 1
            clip: true
            model: root.repos

            ScrollBar.vertical: ScrollBar {
                width: Style.scrollBarWidth
                policy: ScrollBar.AsNeeded
            }

            delegate: Item {
                id: repoDelegate
                required property var modelData
                required property int index

                width: repoListView.width - (repoListView.ScrollBar.vertical.visible ? Style.scrollBarWidth : 0)
                height: delegateContent.implicitHeight + Style.spacingMedium

                Rectangle {
                    anchors.fill: parent
                    color: repoMouseArea.containsMouse ? Style.listViewHoverRowBackgroundColor : "transparent"

                    MouseArea {
                        id: repoMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            // Toggle enabled state
                            if (root.repoManager) {
                                var enabled = repoDelegate.modelData.enabled
                                root.repoManager.setRepoEnabled(
                                    repoDelegate.modelData.owner,
                                    repoDelegate.modelData.repo,
                                    !enabled
                                )
                                // Refresh the list
                                root.repos = root.repoManager.githubRepos
                            }
                        }
                    }

                    RowLayout {
                        id: delegateContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.spacingMedium
                        anchors.rightMargin: Style.spacingMedium
                        spacing: Style.spacingMedium

                        CheckBox {
                            id: repoCheckBox
                            checked: repoDelegate.modelData.enabled
                            onClicked: {
                                if (root.repoManager) {
                                    root.repoManager.setRepoEnabled(
                                        repoDelegate.modelData.owner,
                                        repoDelegate.modelData.repo,
                                        checked
                                    )
                                    root.repos = root.repoManager.githubRepos
                                }
                            }

                            Accessible.role: Accessible.CheckBox
                            Accessible.name: repoDelegate.modelData.fullName
                            Accessible.checked: checked
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingXXSmall

                            Text {
                                text: repoDelegate.modelData.fullName
                                font.pixelSize: Style.fontSizeFormLabel
                                font.family: Style.fontFamilyBold
                                font.bold: true
                                color: repoDelegate.modelData.enabled ? Style.formLabelColor : Style.textMetadataColor
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            // Branch display (when not editing)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                visible: root.editingRepoOwner !== repoDelegate.modelData.owner ||
                                         root.editingRepoName !== repoDelegate.modelData.repo

                                Text {
                                    text: qsTr("Branch: %1").arg(repoDelegate.modelData.defaultBranch)
                                    font.pixelSize: Style.fontSizeCaption
                                    font.family: Style.fontFamily
                                    color: Style.textDescriptionColor
                                }

                                Text {
                                    text: qsTr("(edit)")
                                    font.pixelSize: Style.fontSizeCaption
                                    font.family: Style.fontFamily
                                    color: Style.laerdalBlue
                                    font.underline: editLinkMouseArea.containsMouse

                                    MouseArea {
                                        id: editLinkMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.editingRepoOwner = repoDelegate.modelData.owner
                                            root.editingRepoName = repoDelegate.modelData.repo
                                            root.editingRepoBranch = repoDelegate.modelData.defaultBranch
                                        }
                                    }

                                    Accessible.role: Accessible.Link
                                    Accessible.name: qsTr("Edit branch for %1").arg(repoDelegate.modelData.fullName)
                                }
                            }

                            // Branch edit (when editing this repo)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                visible: root.editingRepoOwner === repoDelegate.modelData.owner &&
                                         root.editingRepoName === repoDelegate.modelData.repo

                                Text {
                                    text: qsTr("Branch:")
                                    font.pixelSize: Style.fontSizeCaption
                                    font.family: Style.fontFamily
                                    color: Style.textDescriptionColor
                                }

                                ImTextField {
                                    id: editBranchField
                                    Layout.preferredWidth: 120
                                    Layout.preferredHeight: 28
                                    text: root.editingRepoBranch
                                    onTextChanged: root.editingRepoBranch = text
                                    font.pixelSize: Style.fontSizeCaption
                                }

                                ImButton {
                                    text: qsTr("Save")
                                    Layout.preferredHeight: 28
                                    font.pixelSize: Style.fontSizeCaption
                                    onClicked: {
                                        if (root.repoManager && root.editingRepoBranch.length > 0) {
                                            root.repoManager.setDefaultBranch(
                                                root.editingRepoOwner,
                                                root.editingRepoName,
                                                root.editingRepoBranch
                                            )
                                            root.repos = root.repoManager.githubRepos
                                            root.editingRepoOwner = ""
                                            root.editingRepoName = ""
                                            root.editingRepoBranch = ""
                                        }
                                    }
                                }

                                Text {
                                    text: qsTr("Cancel")
                                    font.pixelSize: Style.fontSizeCaption
                                    font.family: Style.fontFamily
                                    color: Style.laerdalBlue
                                    font.underline: cancelLinkMouseArea.containsMouse

                                    MouseArea {
                                        id: cancelLinkMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.editingRepoOwner = ""
                                            root.editingRepoName = ""
                                            root.editingRepoBranch = ""
                                        }
                                    }
                                }
                            }
                        }

                        // Remove button
                        ImCloseButton {
                            useAnchors: false
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            visible: root.editingRepoOwner !== repoDelegate.modelData.owner ||
                                     root.editingRepoName !== repoDelegate.modelData.repo
                            onClicked: {
                                if (root.repoManager) {
                                    root.repoManager.removeGitHubRepo(
                                        repoDelegate.modelData.owner,
                                        repoDelegate.modelData.repo
                                    )
                                    root.repos = root.repoManager.githubRepos
                                }
                            }
                            Accessible.name: qsTr("Remove repository")
                        }
                    }
                }

                // Separator
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.spacingMedium
                    anchors.rightMargin: Style.spacingMedium
                    height: 1
                    color: Style.titleSeparatorColor
                    visible: repoDelegate.index < repoListView.count - 1
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                text: qsTr("No repositories configured.\nClick 'Add Repository' to add one.")
                font.pixelSize: Style.fontSizeDescription
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
                horizontalAlignment: Text.AlignHCenter
                visible: repoListView.count === 0
            }
        }
    }

    // Add repository form (collapsible)
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacingSmall
        visible: root.showAddForm

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Style.titleSeparatorColor
        }

        Text {
            text: qsTr("Add Repository")
            font.pixelSize: Style.fontSizeFormLabel
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingSmall

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacingXXSmall

                Text {
                    text: qsTr("Owner")
                    font.pixelSize: Style.fontSizeCaption
                    font.family: Style.fontFamily
                    color: Style.textDescriptionColor
                }

                ComboBox {
                    id: ownerCombo
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.buttonHeightStandard
                    editable: true
                    model: ["Laerdal-Medical", "Laerdal"]
                    currentIndex: -1
                    onActivated: function(index) {
                        root.newRepoOwner = model[index]
                    }
                    onEditTextChanged: root.newRepoOwner = editText

                    font.pixelSize: Style.fontSizeFormLabel
                    font.family: Style.fontFamily

                    background: Rectangle {
                        color: Style.mainBackgroundColor
                        border.color: ownerCombo.activeFocus ? Style.laerdalBlue : Style.popupBorderColor
                        border.width: 1
                        radius: 4
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacingXXSmall

                Text {
                    text: qsTr("Repository")
                    font.pixelSize: Style.fontSizeCaption
                    font.family: Style.fontFamily
                    color: Style.textDescriptionColor
                }

                ComboBox {
                    id: repoCombo
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.buttonHeightStandard
                    editable: true
                    model: ["simpad-plus-top", "simserver-mcbapp", "simpad-app-next"]
                    currentIndex: -1
                    onActivated: function(index) {
                        root.newRepoName = model[index]
                    }
                    onEditTextChanged: root.newRepoName = editText

                    font.pixelSize: Style.fontSizeFormLabel
                    font.family: Style.fontFamily

                    background: Rectangle {
                        color: Style.mainBackgroundColor
                        border.color: repoCombo.activeFocus ? Style.laerdalBlue : Style.popupBorderColor
                        border.width: 1
                        radius: 4
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 100
                spacing: Style.spacingXXSmall

                Text {
                    text: qsTr("Branch")
                    font.pixelSize: Style.fontSizeCaption
                    font.family: Style.fontFamily
                    color: Style.textDescriptionColor
                }

                ImTextField {
                    id: branchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.buttonHeightStandard
                    placeholderText: qsTr("(auto)")
                    text: root.newRepoBranch
                    onTextChanged: root.newRepoBranch = text
                }
            }
        }

        // Buttons row below form fields
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingSmall

            Item { Layout.fillWidth: true }

            ImButton {
                text: qsTr("Cancel")
                Layout.preferredHeight: Style.buttonHeightStandard
                onClicked: {
                    root.showAddForm = false
                    root.newRepoOwner = ""
                    root.newRepoName = ""
                    root.newRepoBranch = ""
                    ownerCombo.currentIndex = -1
                    repoCombo.currentIndex = -1
                }
            }

            ImButtonRed {
                text: qsTr("Add")
                Layout.preferredHeight: Style.buttonHeightStandard
                enabled: root.newRepoOwner.length > 0 && root.newRepoName.length > 0
                onClicked: {
                    if (root.repoManager && root.newRepoOwner && root.newRepoName) {
                        // If branch is empty or "main", auto-detect from GitHub
                        if (root.newRepoBranch.length === 0 || root.newRepoBranch === "main") {
                            root.repoManager.addGitHubRepoWithAutoDetect(
                                root.newRepoOwner,
                                root.newRepoName
                            )
                            // Note: repos list will be updated via Connections when reposChanged fires
                        } else {
                            // Use the specified branch (synchronous add)
                            root.repoManager.addGitHubRepo(
                                root.newRepoOwner,
                                root.newRepoName,
                                root.newRepoBranch
                            )
                        }
                        root.showAddForm = false
                        root.newRepoOwner = ""
                        root.newRepoName = ""
                        root.newRepoBranch = ""
                        ownerCombo.currentIndex = -1
                        repoCombo.currentIndex = -1
                    }
                }
            }
        }
    }

    // Summary text
    Text {
        text: {
            var enabledCount = 0
            for (var i = 0; i < root.repos.length; i++) {
                if (root.repos[i].enabled) enabledCount++
            }
            return qsTr("%1 of %2 repositories enabled").arg(enabledCount).arg(root.repos.length)
        }
        font.pixelSize: Style.fontSizeCaption
        font.family: Style.fontFamily
        color: Style.textMetadataColor
        Layout.fillWidth: true
        visible: !root.showAddForm
    }

    // Footer with action buttons
    footer: RowLayout {
        width: parent.width
        height: Style.buttonHeightStandard + (Style.cardPadding * 2)
        spacing: Style.spacingMedium
        visible: !root.showAddForm

        // Left padding
        Item { Layout.preferredWidth: Style.cardPadding }

        ImButton {
            text: qsTr("Add Repository...")
            onClicked: root.showAddForm = true
            accessibleDescription: qsTr("Add a new GitHub repository to search")
            Layout.preferredHeight: Style.buttonHeightStandard
        }

        Item { Layout.fillWidth: true }

        ImButtonRed {
            text: qsTr("Close")
            onClicked: root.close()
            accessibleDescription: qsTr("Close the repository selection dialog")
            Layout.preferredHeight: Style.buttonHeightStandard
        }

        // Right padding
        Item { Layout.preferredWidth: Style.cardPadding }
    }
}
