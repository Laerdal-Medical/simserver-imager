/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import RpiImager

ConfirmDialog {
    id: popup

    title: qsTr("Content Repository")

    // Dynamic width based on widest radio button or button row
    // Updates automatically when language/text changes
    implicitWidth: Math.max(
        Math.max(radioOfficial.naturalWidth, radioCustomFile.naturalWidth, radioCustomUri.naturalWidth),
        400
    ) + Style.cardPadding * 4  // Double padding: contentLayout + optionsLayout margins

    // Confirm dialog button configuration
    cancelText: CommonStrings.cancel
    confirmText: qsTr("Apply & Restart")
    cancelAccessibleDescription: qsTr("Close the repository dialog without changing the content source")
    confirmAccessibleDescription: qsTr("Apply the new content repository and restart the wizard from the beginning")

    // Use destructive styling for Apply button
    destructiveConfirm: true

    // Enable/disable confirm button based on selection validity
    confirmEnabled: (radioOfficial.checked
                 || (radioCustomFile.checked && popup.selectedRepo.toString() !== "")
                 || (radioCustomUri.checked && fieldCustomUri.isValid))
                 // Disable while write is in progress to prevent restarting during write
                 && (imageWriter.writeState === ImageWriter.Idle ||
                     imageWriter.writeState === ImageWriter.Succeeded ||
                     imageWriter.writeState === ImageWriter.Failed ||
                     imageWriter.writeState === ImageWriter.Cancelled)

    // imageWriter is inherited from BaseDialog
    property var wizardContainer: null

    property bool initialized: false
    property url selectedRepo: ""
    property string customRepoUri: ""
    property string originalRepo: ""

    // Register focus groups when component is ready
    // Note: ConfirmDialog already registers "content" and "buttons" groups
    Component.onCompleted: {
        registerFocusGroup("sourceTypes", function(){
            return [radioOfficial, radioCustomFile, radioCustomUri]
        }, 1)
        registerFocusGroup("customFile", function(){
            return radioCustomFile.checked ? [fieldCustomRepository, browseButton] : []
        }, 2)
        registerFocusGroup("customUri", function(){
            return radioCustomUri.checked ? [fieldCustomUri] : []
        }, 3)
    }

    Connections {
        target: imageWriter
        function onFileSelected(fileUrl) {
            popup.selectedRepo = fileUrl
        }
    }

    // Options section
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: optionsLayout.implicitHeight + Style.cardPadding

        ColumnLayout {
            id: optionsLayout
            anchors.fill: parent
            anchors.margins: Style.cardPadding
            spacing: Style.spacingMedium

            WizardFormLabel {
                text: qsTr("Repository source:")
            }

            ButtonGroup { id: repoGroup }

            ImRadioButton {
                id: radioOfficial
                text: "Laerdal CDN (default)"
                accessibleDescription: qsTr("Use the official Laerdal operating system repository")
                checked: true
                ButtonGroup.group: repoGroup
                Layout.fillWidth: true  // Enable text wrapping for long translations
            }

            ImRadioButton {
                id: radioCustomFile
                text: qsTr("Use custom file")
                accessibleDescription: qsTr("Load operating system list from a JSON file on your computer")
                checked: false
                ButtonGroup.group: repoGroup
                Layout.fillWidth: true  // Enable text wrapping for long translations
                onCheckedChanged: {
                    if (checked) {
                        Qt.callLater(function() {
                            fieldCustomRepository.forceActiveFocus()
                        })
                    }
                }
            }

            ImRadioButton {
                id: radioCustomUri
                text: qsTr("Use custom URL")
                accessibleDescription: qsTr("Download operating system list from a custom web address")
                checked: false
                ButtonGroup.group: repoGroup
                Layout.fillWidth: true  // Enable text wrapping for long translations
                onCheckedChanged: {
                    if (checked) {
                        Qt.callLater(function() {
                            fieldCustomUri.forceActiveFocus()
                        })
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacingMedium
                visible: radioCustomFile.checked

                ImTextField {
                    id: fieldCustomRepository
                    text: selectedRepo !== "" ? UrlFmt.display(selectedRepo) : ""
                    Layout.fillWidth: true
                    placeholderText: qsTr("Please select a custom repository json file")
                    font.pixelSize: Style.fontSizeInput
                    readOnly: true
                    activeFocusOnTab: true
                }

                ImButton {
                    id: browseButton
                    text: CommonStrings.browse
                    accessibleDescription: qsTr("Select a custom repository JSON file from your computer")
                    Layout.minimumWidth: 80
                    activeFocusOnTab: true
                    onClicked: {
                        // Prefer native file dialog via Imager's wrapper, but only if available
                        if (imageWriter.nativeFileDialogAvailable()) {
                            // Defer opening the native dialog until after the current event completes
                            Qt.callLater(function () {
                                imageWriter.openFileDialog(qsTr("Select Repository"), CommonStrings.repoFiltersString);
                            });
                        } else {
                            // Fallback to QML dialog (forced non-native)
                            repoFileDialog.open();
                        }
                    }
                }
            }

            ImTextField {
                id: fieldCustomUri
                visible: radioCustomUri.checked
                Layout.fillWidth: true
                text: popup.customRepoUri
                placeholderText: "https://example.com/repo.json"
                font.pixelSize: Style.fontSizeInput
                activeFocusOnTab: true
                inputMethodHints: Qt.ImhUrlCharactersOnly

                // Use ImageWriter's validation method for consistency
                property bool isValid: popup.imageWriter && popup.imageWriter.isValidRepoUrl(text)
            }
        }
    }

    // Handle accepted (confirm button clicked)
    onAccepted: {
        popup.applySettings()
    }

    // Handle rejected (cancel button clicked)
    onRejected: {
        popup.initialized = false
    }

    Connections {
        target: repoGroup
        function onCheckedButtonChanged() {
            popup.rebuildFocusOrder()
        }
    }

    function initialize() {
        if (!initialized) {
            initialized = true

            if (imageWriter.customRepo()) {
                // Get URL as string to check the scheme
                var repoStr = imageWriter.osListUrl().toString()
                if (repoStr.startsWith("file:")) {
                    radioOfficial.checked = false
                    radioCustomFile.checked = true
                    radioCustomUri.checked = false
                    selectedRepo = imageWriter.osListUrl()
                    originalRepo = repoStr
                } else if (repoStr.startsWith("http:") || repoStr.startsWith("https:")) {
                    radioOfficial.checked = false
                    radioCustomFile.checked = false
                    radioCustomUri.checked = true
                    customRepoUri = repoStr
                    originalRepo = repoStr
                } else {
                    radioOfficial.checked = true
                    radioCustomFile.checked = false
                    radioCustomUri.checked = false
                    originalRepo = ""
                }
            } else {
                radioOfficial.checked = true
                radioCustomFile.checked = false
                radioCustomUri.checked = false
                selectedRepo = ""
                customRepoUri = ""
                originalRepo = ""
            }

            // Ensure focus order is built after initial state
            popup.rebuildFocusOrder()
        }
    }

    function applySettings() {
        // Save settings to ImageWriter
        // Only save repository setting if it has actually changed
        if (radioOfficial.checked && originalRepo !== "") {
            imageWriter.refreshOsListFromDefaultUrl()
            // reset wizard to device selection because the repository changed
            wizardContainer.resetWizard()
        } else if (radioCustomFile.checked && originalRepo !== selectedRepo.toString()) {
            imageWriter.refreshOsListFrom(selectedRepo)
            // reset wizard to device selection because the repository changed
            wizardContainer.resetWizard()
        } else if (radioCustomUri.checked && originalRepo !== fieldCustomUri.text) {
            // QML auto-converts string to QUrl for C++ method
            imageWriter.refreshOsListFrom(fieldCustomUri.text)
            // reset wizard to device selection because the repository changed
            wizardContainer.resetWizard()
        }
        initialized = false
    }

    onOpened: {
        initialize()
    }

    property alias repoFileDialog: repoFileDialog

    ImFileDialog {
        id: repoFileDialog
        imageWriter: popup.imageWriter
        dialogTitle: qsTr("Select custom repository")
        nameFilters: CommonStrings.repoFiltersList
        onAccepted: {
            popup.selectedRepo = selectedFile;
        }
        onRejected:
        // No-op; user cancelled
        {}
    }
}
