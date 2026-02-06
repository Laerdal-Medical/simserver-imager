/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Laerdal Medical
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import RpiImager

BaseDialog {
    id: root

    property var githubAuth: null

    title: qsTr("Sign in with GitHub")
    width: 480
    height: 320

    // OAuth Device Flow states
    property string userCode: ""
    property string verificationUrl: ""
    property bool isPolling: false
    property bool hasError: false
    property string errorMessage: ""

    // State machine: idle, waiting_for_code, polling, success, error
    property string authState: "idle"

    Component.onCompleted: {
        registerFocusGroup("dialog_content", function() {
            if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                return [titleLabel, instructionText]
            }
            return []
        }, 0)

        registerFocusGroup("dialog_buttons", function() {
            var buttons = []
            if (tryAgainButton.visible && tryAgainButton.enabled) buttons.push(tryAgainButton)
            if (copyCodeButton.visible && copyCodeButton.enabled) buttons.push(copyCodeButton)
            if (openGitHubButton.visible && openGitHubButton.enabled) buttons.push(openGitHubButton)
            if (cancelButton.visible) buttons.push(cancelButton)
            return buttons
        }, 1)
    }

    // Connect to GitHub auth signals
    Connections {
        target: root.githubAuth
        enabled: root.githubAuth !== null

        function onUserCodeChanged() {
            root.userCode = root.githubAuth.userCode
            root.verificationUrl = root.githubAuth.verificationUrl
            root.authState = "waiting_for_code"
            root.hasError = false
            root.errorMessage = ""
        }

        function onAuthSuccess() {
            root.authState = "success"
            // Close dialog after brief delay to show success
            successCloseTimer.start()
        }

        function onAuthError(error) {
            root.authState = "error"
            root.hasError = true
            root.errorMessage = error
            root.isPolling = false
        }
    }

    Timer {
        id: successCloseTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.close()
        }
    }

    onOpened: {
        // Start device flow when dialog opens
        root.authState = "idle"
        root.userCode = ""
        root.verificationUrl = ""
        root.hasError = false
        root.errorMessage = ""

        if (githubAuth) {
            githubAuth.startDeviceFlow()
        }
    }

    onClosed: {
        // Cancel auth if still in progress
        if (root.authState !== "success" && githubAuth) {
            githubAuth.cancelAuth()
        }
        // Reset state
        root.authState = "idle"
        root.userCode = ""
        root.verificationUrl = ""
        root.hasError = false
        root.errorMessage = ""
    }

    // Dialog content
    Text {
        id: titleLabel
        text: {
            switch (root.authState) {
                case "idle": return qsTr("Initiating GitHub sign-in...")
                case "waiting_for_code": return qsTr("Enter code on GitHub")
                case "polling": return qsTr("Waiting for authorization...")
                case "success": return qsTr("Successfully signed in!")
                case "error": return qsTr("Sign-in failed")
                default: return qsTr("Sign in with GitHub")
            }
        }
        font.pixelSize: Style.fontSizeHeading
        font.family: Style.fontFamilyBold
        font.bold: true
        color: root.authState === "error" ? Style.formLabelErrorColor : Style.formLabelColor
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Accessible.role: Accessible.Heading
        Accessible.name: text
        Accessible.ignored: false
        Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
        focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
        activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
    }

    // Loading state
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 80
        visible: root.authState === "idle"

        ImBusyIndicator {
            anchors.centerIn: parent
            running: root.authState === "idle"
        }
    }

    // Code display state
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacingMedium
        visible: root.authState === "waiting_for_code" || root.authState === "polling"

        Text {
            id: instructionText
            text: qsTr("Open GitHub in your browser and enter the following code:")
            font.pixelSize: Style.fontSizeFormLabel
            font.family: Style.fontFamily
            color: Style.formLabelColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Accessible.ignored: false
            Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
            focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
        }

        // User code display
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: Style.listViewHoverRowBackgroundColor
            radius: Style.sectionBorderRadius
            border.color: Style.popupBorderColor
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: root.userCode
                font.pixelSize: Style.fontSizeTitle
                font.family: Style.fontFamilyBold
                font.bold: true
                font.letterSpacing: 4
                color: Style.laerdalBlue
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("Authorization code: %1").arg(root.userCode)
            }
        }

        // Verification URL
        Text {
            text: qsTr("Go to: %1").arg(root.verificationUrl)
            font.pixelSize: Style.fontSizeCaption
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        // Polling indicator
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingSmall
            visible: root.authState === "polling"

            ImBusyIndicator {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                running: root.authState === "polling"
            }

            Text {
                text: qsTr("Waiting for you to authorize on GitHub...")
                font.pixelSize: Style.fontSizeCaption
                font.family: Style.fontFamily
                color: Style.textDescriptionColor
            }
        }
    }

    // Success state
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacingMedium
        visible: root.authState === "success"

        RowLayout {
            id: successRow
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.spacingSmall

            Rectangle {
                width: 24
                height: 24
                radius: 12
                color: "#28a745"

                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    font.pixelSize: 16
                    font.bold: true
                    color: "white"
                }
            }

            Text {
                text: qsTr("Signed in successfully")
                font.pixelSize: Style.fontSizeFormLabel
                font.family: Style.fontFamilyBold
                font.bold: true
                color: "#28a745"
            }
        }
    }

    // Error state
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacingMedium
        visible: root.authState === "error"

        Text {
            text: root.errorMessage || qsTr("An error occurred during sign-in.")
            font.pixelSize: Style.fontSizeFormLabel
            font.family: Style.fontFamily
            color: Style.formLabelErrorColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    // Footer with action buttons
    footer: RowLayout {
        width: parent.width
        height: tryAgainButton.implicitHeight + (Style.cardPadding * 2)
        Layout.margins: Style.cardPadding
        spacing: Style.spacingMedium

        // Left padding
        Item { Layout.preferredWidth: Style.cardPadding / 2 }

        // Try Again button (only in error state)
        ImButton {
            id: tryAgainButton
            text: qsTr("Try Again")
            accessibleDescription: qsTr("Retry GitHub sign-in")
            Layout.preferredHeight: Style.buttonHeightStandard
            visible: root.authState === "error"
            activeFocusOnTab: true

            onClicked: {
                root.authState = "idle"
                root.hasError = false
                root.errorMessage = ""
                if (root.githubAuth) {
                    root.githubAuth.startDeviceFlow()
                }
            }
        }

        // Copy Code button (in waiting_for_code or polling states)
        ImButton {
            id: copyCodeButton
            text: qsTr("Copy Code")
            accessibleDescription: qsTr("Copy the authorization code to clipboard")
            Layout.preferredHeight: Style.buttonHeightStandard
            visible: root.authState === "waiting_for_code" || root.authState === "polling"
            activeFocusOnTab: true

            onClicked: {
                if (root.imageWriter) {
                    root.imageWriter.copyToClipboard(root.userCode)
                }
            }
        }

        // Open GitHub button (in waiting_for_code or polling states)
        ImButtonRed {
            id: openGitHubButton
            text: qsTr("Open GitHub")
            accessibleDescription: qsTr("Open GitHub authorization page in your browser")
            Layout.preferredHeight: Style.buttonHeightStandard
            visible: root.authState === "waiting_for_code" || root.authState === "polling"
            activeFocusOnTab: true

            onClicked: {
                if (root.imageWriter) {
                    root.imageWriter.openUrl(root.verificationUrl)
                }
                // Start polling after user opens GitHub
                root.authState = "polling"
            }
        }

        Item { Layout.fillWidth: true }

        // Cancel button (always visible except on success)
        ImButton {
            id: cancelButton
            text: qsTr("Cancel")
            accessibleDescription: qsTr("Cancel GitHub sign-in")
            Layout.preferredHeight: Style.buttonHeightStandard
            visible: root.authState !== "success"
            activeFocusOnTab: true

            onClicked: {
                root.close()
            }
        }

        // Right padding
        Item { Layout.preferredWidth: Style.cardPadding / 2 }
    }
}
