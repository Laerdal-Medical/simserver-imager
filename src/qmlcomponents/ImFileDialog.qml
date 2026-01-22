/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */


import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import RpiImager

BaseDialog {
    id: dialog

    // Public API (aligning loosely with FileDialog)
    property string dialogTitle: qsTr("Select File")
    property url currentFolder: ""  // Empty by default, will be set in open()
    // Back-compat property name some callers may set
    property url folder: currentFolder
    property var nameFilters: [] // ["Images (*.png *.jpg)", "All files (*)"]
    property url selectedFile: ""

    // Save dialog mode - when true, shows filename input and hides file list
    property bool isSaveDialog: false
    property string suggestedFilename: ""

    // Use Dialog's built-in accepted/rejected signals; do not redeclare to avoid overrides

    property string _currentFilename: suggestedFilename

    // Settings for persisting last folder
    Settings {
        id: dialogSettings
        category: "ImFileDialog"
        property string lastOpenFolder: ""
        property string lastSaveFolder: ""
    }

    function open() {
        // For save dialogs, initialize filename from suggestion
        if (isSaveDialog) {
            _currentFilename = suggestedFilename
        }

        // Restore last used folder, or use sensible default
        var savedFolder = isSaveDialog ? dialogSettings.lastSaveFolder : dialogSettings.lastOpenFolder
        if (savedFolder && savedFolder.length > 0) {
            dialog.currentFolder = savedFolder
        } else if (String(dialog.currentFolder).length === 0) {
            // No saved folder and no folder set - use Downloads as default
            var defaultFolder = String(StandardPaths.writableLocation(StandardPaths.DownloadLocation))
            if (defaultFolder && defaultFolder.length > 0) {
                dialog.currentFolder = (Qt.platform.os === "windows")
                    ? ("file:///" + defaultFolder)
                    : ("file://" + defaultFolder)
            } else {
                // Fallback to home if Downloads not available
                var homeFolder = String(StandardPaths.writableLocation(StandardPaths.HomeLocation))
                dialog.currentFolder = (Qt.platform.os === "windows")
                    ? ("file:///" + homeFolder)
                    : ("file://" + homeFolder)
            }
        }

        dialog.visible = true
    }
    function close() { dialog.visible = false }
    
    // Build the full file path from current folder and filename (for save mode)
    function _buildFilePath() {
        var folder = _toDisplayPath(currentFolder)
        var filename = String(_currentFilename).trim()
        if (!filename) return ""
        // Ensure folder ends with /
        if (!folder.endsWith("/")) folder += "/"
        return folder + filename
    }

    // Override BaseDialog defaults for file dialog specific sizing
    // Use most of the available parent space for better usability
    width: parent ? Math.max(600, parent.width * 0.85) : 720
    height: parent ? Math.max(400, parent.height * 0.85) : 540

    // Convert Qt-style nameFilters to FolderListModel.nameFilters
    function _extractGlobs(filters) {
        var out = []
        for (var i = 0; i < filters.length; i++) {
            var f = String(filters[i])
            var lb = f.indexOf("(")
            var rb = f.indexOf(")")
            if (lb >= 0 && rb > lb) {
                var inner = f.substring(lb+1, rb)
                var globs = inner.split(/\s+/).filter(g => g.length > 0)
                out = out.concat(globs)
            } else if (f.indexOf("*") >= 0) {
                out.push(f)
            }
        }
        if (out.length === 0) out = ["*"]
        return out
    }

    // Normalize a typed path to a file URL
    function _toFileUrl(path) {
        if (!path)
            return "";
        var s = String(path).trim()
        // Expand ~ to home
        if (s === "~" || s.indexOf("~/") === 0) {
            var home = String(StandardPaths.writableLocation(StandardPaths.HomeLocation))
            s = home + s.substring(1)
        }
        if (s.indexOf("file://") === 0)
            return s
        // Allow absolute paths
        if (s.indexOf("/") === 0)
            return "file://" + s
        return s // fallback; caller may provide URL
    }

    // Convert a URL to a display path (strip file:// scheme)
    function _toDisplayPath(u) {
        var s = String(u || "").trim()
        if (s.indexOf("file://") === 0) {
            var p = s.substring(7)
            return p.length > 0 ? p : "/"
        }
        return s
    }

    // Get enforced image globs from provided filters; otherwise return defaults
    function _getImageGlobs(filters) {
        var globs = dialog._extractGlobs(filters)
        var specific = globs.filter(function(g) { return g !== "*" })
        if (specific.length > 0)
            return specific
        // Default accepted image formats
        return ["*.img", "*.zip", "*.iso", "*.gz", "*.xz", "*.zst", "*.wic"]
    }

    // Return true if the given url/path resolves to filesystem root
    function _isRoot(u) {
        var s = String(u || "").trim()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        // Normalize trailing slashes
        while (s.length > 1 && s.endsWith("/")) s = s.substring(0, s.length - 1)
        return s === "/"
    }

    // Compute normalized parent folder URL without '..' segments
    function _parentUrl(u) {
        var s = String(u || "").trim()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        // Strip trailing slashes
        while (s.length > 1 && s.endsWith("/")) s = s.substring(0, s.length - 1)
        if (s === "/") return "file:///"
        var slash = s.lastIndexOf("/")
        if (slash <= 0) return "file:///"
        var parent = s.substring(0, slash)
        if (parent.length === 0) parent = "/"
        return "file://" + parent
    }

    function _canGoUp() { return !_isRoot(dialog.currentFolder) }
    function _goUp() { if (_canGoUp()) dialog.currentFolder = _parentUrl(dialog.currentFolder) }

    // Data models
    FolderListModel {
        id: folderModel
        folder: dialog.currentFolder
        showDirs: true
        showFiles: true
        showDotAndDotDot: true
        nameFilters: dialog._extractGlobs(dialog.nameFilters)
        sortField: FolderListModel.Name
        sortReversed: false
    }

    // Directories-only model for left pane (subfolders of current folder)
    FolderListModel {
        id: dirsOnlyModel
        folder: dialog.currentFolder
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        sortReversed: false
        nameFilters: ["*"]
    }

    // Files-only model for right pane (files of current folder)
    FolderListModel {
        id: filesOnlyModel
        folder: dialog.currentFolder
        showDirs: false
        showFiles: true
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        sortReversed: false
        nameFilters: dialog._getImageGlobs(dialog.nameFilters)
    }

    // Places model for left pane
    ListModel { id: placesModel }

    // Parent path model for folder breadcrumb navigation
    ListModel { id: parentPathModel }

    // Rebuild folder tree model - shows parent path + current folder + subfolders
    function _rebuildFolderTreeModel() {
        parentPathModel.clear()
        var path = _toDisplayPath(dialog.currentFolder)
        if (!path || path.length === 0) return

        // Split path into components
        var parts = path.split("/").filter(function(p) { return p.length > 0 })

        // Build cumulative paths - start from root
        var cumulative = ""

        // Add root
        parentPathModel.append({
            label: "/",
            url: "file:///",
            isCurrentFolder: parts.length === 0,
            isSubfolder: false,
            depth: 0
        })

        // Add each path component (parent folders + current)
        for (var i = 0; i < parts.length; i++) {
            cumulative += "/" + parts[i]
            var isLast = (i === parts.length - 1)
            parentPathModel.append({
                label: parts[i],
                url: "file://" + cumulative,
                isCurrentFolder: isLast,
                isSubfolder: false,
                depth: i + 1
            })
        }

        // Add subfolders from dirsOnlyModel (will be populated async)
        _addSubfoldersToModel()
    }

    // Add subfolders to the folder tree model
    function _addSubfoldersToModel() {
        var path = _toDisplayPath(dialog.currentFolder)
        var parts = path.split("/").filter(function(p) { return p.length > 0 })
        var subfolderDepth = parts.length + 1

        // Remove existing subfolders first
        for (var i = parentPathModel.count - 1; i >= 0; i--) {
            if (parentPathModel.get(i).isSubfolder) {
                parentPathModel.remove(i)
            }
        }

        // Add subfolders from the FolderListModel
        for (var j = 0; j < dirsOnlyModel.count; j++) {
            var folderName = dirsOnlyModel.get(j, "fileName")
            var folderUrl = dirsOnlyModel.get(j, "fileUrl")
            parentPathModel.append({
                label: folderName,
                url: String(folderUrl),
                isCurrentFolder: false,
                isSubfolder: true,
                depth: subfolderDepth
            })
        }
    }

    // Watch for dirsOnlyModel changes to update subfolders
    Connections {
        target: dirsOnlyModel
        function onStatusChanged() {
            if (dirsOnlyModel.status === FolderListModel.Ready) {
                _addSubfoldersToModel()
            }
        }
    }

    onCurrentFolderChanged: {
        // Ensure address bar follows folder changes
        pathField.text = dialog._toDisplayPath(dialog.currentFolder)
        // Reset selection when navigating
        dialog.selectedFile = ""
        // Rebuild folder tree (parents + current + subfolders)
        _rebuildFolderTreeModel()
    }

    // Override escape handler to call rejected signal
    function escapePressed() {
        dialog.close()
        dialog.rejected()
    }
    
    // Initialize and register focus groups when component is ready
    Component.onCompleted: {
        // Override contentLayout to fill dialog and maximize space
        if (contentLayout) {
            contentLayout.anchors.fill = contentLayout.parent
            contentLayout.anchors.margins = 10
            contentLayout.spacing = 4
        }
        
        // Add places based on dialog mode
        if (dialog.isSaveDialog) {
            // Save dialogs get common save locations
            var docsPath = String(StandardPaths.writableLocation(StandardPaths.DocumentsLocation))
            if (docsPath && docsPath.length > 0) {
                placesModel.append({ label: "📄 " + qsTr("Documents"), url: "file://" + docsPath })
            }

            var downloadPath = String(StandardPaths.writableLocation(StandardPaths.DownloadLocation))
            if (downloadPath && downloadPath.length > 0) {
                placesModel.append({ label: "📥 " + qsTr("Downloads"), url: "file://" + downloadPath })
            }

            var homePath = String(StandardPaths.writableLocation(StandardPaths.HomeLocation))
            if (homePath && homePath.length > 0) {
                placesModel.append({ label: "🏠 " + qsTr("Home"), url: "file://" + homePath })
            }
        } else {
            // Open dialogs get removable drives shortcut based on platform
            var removableDrivesPath = ""
            if (Qt.platform.os === "linux") {
                removableDrivesPath = "file:///mnt"
            } else if (Qt.platform.os === "osx" || Qt.platform.os === "darwin") {
                removableDrivesPath = "file:///Volumes"
            } else if (Qt.platform.os === "windows") {
                // On Windows, show root which lists all drives
                removableDrivesPath = "file:///"
            } else {
                // Fallback to root for other platforms
                removableDrivesPath = "file:///"
            }
            placesModel.append({ label: "💾 " + qsTr("Removable drives"), url: removableDrivesPath })
        }
        
        // Initialize path field text and parent path model
        pathField.text = dialog._toDisplayPath(dialog.currentFolder)
        _rebuildFolderTreeModel()

        // Register focus groups - different order for save vs open dialogs
        if (dialog.isSaveDialog) {
            registerFocusGroup("filename", function(){ 
                return [filenameField] 
            }, 0)
            registerFocusGroup("address", function(){ 
                return [pathField] 
            }, 1)
            registerFocusGroup("places", function(){ 
                return [placesList] 
            }, 2)
            registerFocusGroup("folders", function(){ 
                return [parentPathList] 
            }, 3)
            registerFocusGroup("buttons", function(){ 
                return [cancelButton, openButton] 
            }, 4)
        } else {
            registerFocusGroup("address", function(){ 
                return [pathField] 
            }, 0)
            registerFocusGroup("places", function(){ 
                return [placesList] 
            }, 1)
            registerFocusGroup("folders", function(){ 
                return [parentPathList] 
            }, 2)
            registerFocusGroup("navigation", function(){ 
                return [upEntry] 
            }, 3)
            registerFocusGroup("files", function(){ 
                return [filesList] 
            }, 4)
            registerFocusGroup("buttons", function(){ 
                return [cancelButton, openButton] 
            }, 5)
        }
    }

    // Title and address bar on same row
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 6
        spacing: 12
        
        Text {
            id: titleText
            text: dialog.dialogTitle
            font.pixelSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
        }
        
        TextField {
            id: pathField
            Layout.fillWidth: true
            text: dialog._toDisplayPath(dialog.currentFolder)
            placeholderText: qsTr("Enter path or URL…")
            activeFocusOnTab: true
            onAccepted: {
                var newUrl = dialog._toFileUrl(text)
                if (newUrl && newUrl.length > 0) {
                    dialog.currentFolder = newUrl
                }
            }
        }
    }
    
    // Filename input row (only for save dialogs)
    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        spacing: 12
        visible: dialog.isSaveDialog
        
        Text {
            text: qsTr("File name:")
            font.pixelSize: Style.fontSizeFormLabel
            font.family: Style.fontFamily
            color: Style.formLabelColor
        }
        
        TextField {
            id: filenameField
            Layout.fillWidth: true
            text: dialog._currentFilename
            placeholderText: qsTr("Enter filename…")
            activeFocusOnTab: dialog.isSaveDialog
            onTextChanged: {
                dialog._currentFilename = text
            }
            onAccepted: {
                if (text.trim().length > 0) {
                    dialog.selectedFile = dialog._toFileUrl(dialog._buildFilePath())
                    dialog.close()
                    dialog.accepted()
                }
            }
        }
    }

    // Main content with left navigation and file list
    RowLayout {
        id: mainRow
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        // Left navigation pane
        Frame {
            id: leftPane
            Layout.preferredWidth: leftPaneWidth
            Layout.minimumWidth: 120
            Layout.maximumWidth: dialog.width * 0.4
            Layout.fillHeight: true

            // Store the width for resizing
            property real leftPaneWidth: 200
            clip: true
            padding: 8
            background: Rectangle {
                color: Style.mainBackgroundColor
                radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.sectionBorderRadiusEmbedded : Style.sectionBorderRadius
                border.color: Style.popupBorderColor
                border.width: Style.sectionBorderWidth
                antialiasing: true
                clip: true
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                // Places header
                Text {
                    text: qsTr("Places")
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.textDescriptionColor
                    Layout.fillWidth: true
                    Layout.bottomMargin: 2
                }

                ListView {
                    id: placesList
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    clip: true
                    activeFocusOnTab: true
                    model: placesModel
                    currentIndex: -1  // No item selected by default
                    highlightFollowsCurrentItem: true
                    highlight: Rectangle {
                        color: placesList.activeFocus ? Style.listViewHighlightColor : Qt.rgba(0, 0, 0, 0.05)
                        radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.listItemBorderRadiusEmbedded : Style.listItemBorderRadius
                        antialiasing: true
                        visible: placesList.currentIndex >= 0
                    }
                    
                    // Set focus to first item when list receives focus
                    onActiveFocusChanged: {
                        if (activeFocus && currentIndex < 0 && count > 0) {
                            currentIndex = 0
                        }
                    }
                    delegate: ItemDelegate {
                        required property int index
                        required property var model
                        
                        width: (ListView.view ? ListView.view.width : 0)
                        text: model.label
                        highlighted: ListView.isCurrentItem
                        Accessible.role: Accessible.ListItem
                        Accessible.name: text
                        background: Rectangle {
                            color: {
                                if (ListView.isCurrentItem && placesList.activeFocus)
                                    return Style.listViewHighlightColor
                                else if (hovered)
                                    return Style.listViewHoverRowBackgroundColor
                                else
                                    return "transparent"
                            }
                            radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.listItemBorderRadiusEmbedded : Style.listItemBorderRadius
                            antialiasing: true
                        }
                        onClicked: {
                            placesList.currentIndex = index
                            dialog.currentFolder = model.url
                        }
                    }
                    Keys.onUpPressed: {
                        if (currentIndex > 0) {
                            currentIndex--
                        }
                    }
                    Keys.onDownPressed: {
                        if (currentIndex < count - 1) {
                            currentIndex++
                        }
                    }
                    Keys.onEnterPressed: {
                        if (currentIndex >= 0) {
                            dialog.currentFolder = model.get(currentIndex).url
                        }
                    }
                    Keys.onReturnPressed: {
                        if (currentIndex >= 0) {
                            dialog.currentFolder = model.get(currentIndex).url
                        }
                    }
                }

                // Separator line between places and folders
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 8
                    Layout.bottomMargin: 4
                    color: Style.popupBorderColor
                }

                Text {
                    text: qsTr("Folders")
                    font.pixelSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.textDescriptionColor
                    Layout.fillWidth: true
                    Layout.bottomMargin: 2
                }

                // Parent path breadcrumb list - shows path hierarchy with current folder highlighted
                ListView {
                    id: parentPathList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    activeFocusOnTab: true
                    model: parentPathModel
                    spacing: 2
                    currentIndex: -1
                    highlightFollowsCurrentItem: true
                    highlight: Rectangle {
                        color: parentPathList.activeFocus ? Style.listViewHighlightColor : Qt.rgba(0, 0, 0, 0.05)
                        radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.listItemBorderRadiusEmbedded : Style.listItemBorderRadius
                        antialiasing: true
                        visible: parentPathList.currentIndex >= 0
                    }

                    // Set focus to current folder item when list receives focus
                    onActiveFocusChanged: {
                        if (activeFocus && count > 0) {
                            // Focus on the current folder (last item)
                            currentIndex = count - 1
                        }
                    }

                    delegate: ItemDelegate {
                        id: pathDelegate
                        required property int index
                        required property string label
                        required property string url
                        required property bool isCurrentFolder
                        required property bool isSubfolder
                        required property int depth

                        width: (ListView.view ? ListView.view.width : 0)
                        // Current folder: open folder icon, subfolders: closed folder, parents: closed folder
                        text: (pathDelegate.isCurrentFolder ? "📂 " : "📁 ") + pathDelegate.label
                        leftPadding: 8 + (pathDelegate.depth * 12)  // Indent based on depth
                        highlighted: ListView.isCurrentItem
                        Accessible.role: Accessible.ListItem
                        Accessible.name: {
                            if (pathDelegate.isCurrentFolder)
                                return qsTr("Current folder: %1").arg(pathDelegate.label)
                            else if (pathDelegate.isSubfolder)
                                return qsTr("Subfolder: %1").arg(pathDelegate.label)
                            else
                                return qsTr("Parent folder: %1").arg(pathDelegate.label)
                        }
                        background: Rectangle {
                            color: {
                                if (pathDelegate.isCurrentFolder)
                                    return Style.listViewHighlightColor
                                else if (pathDelegate.ListView.isCurrentItem && pathDelegate.ListView.view.activeFocus)
                                    return Style.listViewHighlightColor
                                else if (pathDelegate.hovered)
                                    return Style.listViewHoverRowBackgroundColor
                                else
                                    return "transparent"
                            }
                            radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.listItemBorderRadiusEmbedded : Style.listItemBorderRadius
                            antialiasing: true
                        }
                        contentItem: Text {
                            text: pathDelegate.text
                            font.pixelSize: Style.fontSizeDescription
                            font.family: Style.fontFamily
                            font.bold: pathDelegate.isCurrentFolder
                            color: Style.formLabelColor
                            elide: Text.ElideMiddle
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            if (!pathDelegate.isCurrentFolder) {
                                parentPathList.currentIndex = pathDelegate.index
                                dialog.currentFolder = pathDelegate.url
                            }
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: Style.scrollBarWidth }
                    Keys.onUpPressed: {
                        if (currentIndex > 0) {
                            currentIndex--
                        }
                    }
                    Keys.onDownPressed: {
                        if (currentIndex < count - 1) {
                            currentIndex++
                        }
                    }
                    Keys.onEnterPressed: {
                        if (currentIndex >= 0 && !model.get(currentIndex).isCurrentFolder) {
                            dialog.currentFolder = model.get(currentIndex).url
                        }
                    }
                    Keys.onReturnPressed: {
                        if (currentIndex >= 0 && !model.get(currentIndex).isCurrentFolder) {
                            dialog.currentFolder = model.get(currentIndex).url
                        }
                    }
                }
            }
        }

        // Resizable splitter handle
        Rectangle {
            id: splitter
            Layout.preferredWidth: 6
            Layout.fillHeight: true
            color: splitterMouseArea.containsMouse || splitterMouseArea.pressed ? Style.popupBorderColor : "transparent"

            MouseArea {
                id: splitterMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SplitHCursor

                property real startX: 0
                property real startWidth: 0

                onPressed: function(mouse) {
                    startX = mouse.x
                    startWidth = leftPane.leftPaneWidth
                }

                onPositionChanged: function(mouse) {
                    if (pressed) {
                        var delta = mouse.x - startX
                        var newWidth = startWidth + delta
                        // Clamp to reasonable bounds
                        newWidth = Math.max(120, Math.min(newWidth, mainRow.width - 200))
                        leftPane.leftPaneWidth = newWidth
                    }
                }
            }
        }

        // File list
        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 8
            background: Rectangle {
                color: Style.mainBackgroundColor
                radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.sectionBorderRadiusEmbedded : Style.sectionBorderRadius
                border.color: Style.popupBorderColor
                border.width: Style.sectionBorderWidth
                antialiasing: true
                clip: true
            }

            // Unified scroll area: Up entry, then directories, then files
            ScrollView {
                id: fileListScrollView
                anchors.fill: parent
                activeFocusOnTab: false  // Don't focus the ScrollView itself, only its children
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: Style.scrollBarWidth }
                contentWidth: availableWidth  // Ensure content fills width

                property int currentFileIndex: -1
                
                Keys.onUpPressed: {
                    if (currentFileIndex > 0) {
                        currentFileIndex--
                        // Update selection
                        var fileItem = fileColumn.children[currentFileIndex + 1] // +1 because of up entry
                        if (fileItem && fileItem.fileUrl) {
                            dialog.selectedFile = fileItem.fileUrl
                        }
                    }
                }
                Keys.onDownPressed: {
                    if (currentFileIndex < filesOnlyModel.count - 1) {
                        currentFileIndex++
                        // Update selection
                        var fileItem = fileColumn.children[currentFileIndex + 1] // +1 because of up entry
                        if (fileItem && fileItem.fileUrl) {
                            dialog.selectedFile = fileItem.fileUrl
                        }
                    }
                }
                Keys.onEnterPressed: {
                    if (dialog.selectedFile && String(dialog.selectedFile).length > 0) {
                        dialog.close()
                        dialog.accepted()
                    }
                }
                Keys.onReturnPressed: {
                    if (dialog.selectedFile && String(dialog.selectedFile).length > 0) {
                        dialog.close()
                        dialog.accepted()
                    }
                }

                Column {
                    id: fileColumn
                    width: fileListScrollView.availableWidth
                    spacing: 0

                    // Up entry at top of right pane - always show when not at root
                    ImButton {
                        id: upEntry
                        width: parent.width
                        visible: dialog._canGoUp()
                        height: visible ? implicitHeight : 0
                        text: "↑ " + qsTr("Go up a folder")
                        activeFocusOnTab: true
                        onClicked: dialog._goUp()
                        
                        // Rebuild focus order when visibility changes
                        onVisibleChanged: {
                            if (dialog.rebuildFocusOrder) {
                                Qt.callLater(dialog.rebuildFocusOrder)
                            }
                        }
                        
                        // Custom styling to make it look like a navigation item
                        background: Rectangle {
                            color: upEntry.hovered ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(0, 0, 0, 0.03)
                            radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.listItemBorderRadiusEmbedded : Style.listItemBorderRadius
                            border.width: upEntry.activeFocus ? 2 : 1
                            border.color: upEntry.activeFocus ? Style.focusOutlineColor : Qt.rgba(0, 0, 0, 0.1)
                            antialiasing: true
                        }
                        
                        contentItem: Text {
                            text: upEntry.text
                            font.pixelSize: Style.fontSizeDescription
                            font.family: Style.fontFamily
                            font.italic: true
                            color: Style.textDescriptionColor
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignLeft
                            leftPadding: 4
                        }
                    }

                    // Files list with focus support (hidden in save mode)
                    ListView {
                        id: filesList
                        width: fileColumn.width
                        height: dialog.isSaveDialog ? 0 : contentHeight
                        visible: !dialog.isSaveDialog && filesOnlyModel.count > 0
                        model: filesOnlyModel
                        activeFocusOnTab: !dialog.isSaveDialog && filesOnlyModel.count > 0
                        currentIndex: -1
                        highlightFollowsCurrentItem: true
                        interactive: false
                        
                        highlight: Rectangle {
                            color: filesList.activeFocus ? Style.listViewHighlightColor : Qt.rgba(0, 0, 0, 0.05)
                            radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.listItemBorderRadiusEmbedded : Style.listItemBorderRadius
                            antialiasing: true
                            visible: filesList.currentIndex >= 0
                        }
                        
                        // Set focus to first item when list receives focus
                        onActiveFocusChanged: {
                            if (activeFocus && currentIndex < 0 && count > 0) {
                                currentIndex = 0
                                // Set the selected file to the first file
                                if (count > 0) {
                                    dialog.selectedFile = model.get(0, "fileUrl")
                                }
                            }
                        }

                        // Navigate with arrow keys
                        Keys.onUpPressed: {
                            if (currentIndex > 0) {
                                currentIndex--
                                dialog.selectedFile = model.get(currentIndex, "fileUrl")
                            }
                        }
                        Keys.onDownPressed: {
                            if (currentIndex < count - 1) {
                                currentIndex++
                                dialog.selectedFile = model.get(currentIndex, "fileUrl")
                            }
                        }

                        delegate: ItemDelegate {
                            required property int index
                            required property string fileName
                            required property url fileUrl

                            width: ListView.view.width
                            text: "📄 " + fileName
                            highlighted: ListView.isCurrentItem
                            Accessible.role: Accessible.ListItem
                            Accessible.name: qsTr("File: %1").arg(fileName)
                            background: Rectangle {
                                color: {
                                    if (dialog.selectedFile === fileUrl)
                                        return Style.listViewHighlightColor
                                    else if (ListView.isCurrentItem && filesList.activeFocus)
                                        return Style.listViewHighlightColor
                                    else if (hovered)
                                        return Style.listViewHoverRowBackgroundColor
                                    else
                                        return "transparent"
                                }
                                radius: (dialog.imageWriter && dialog.imageWriter.isEmbeddedMode()) ? Style.listItemBorderRadiusEmbedded : Style.listItemBorderRadius
                                antialiasing: true
                            }
                            onClicked: {
                                filesList.currentIndex = index
                                dialog.selectedFile = fileUrl
                            }
                        }
                        
                        Keys.onReturnPressed: {
                            if (dialog.selectedFile && String(dialog.selectedFile).length > 0) {
                                dialog.close()
                                dialog.accepted()
                            }
                        }
                        Keys.onEnterPressed: {
                            if (dialog.selectedFile && String(dialog.selectedFile).length > 0) {
                                dialog.close()
                                dialog.accepted()
                            }
                        }
                    }

                    // Show message when no files are available (only in open mode)
                    Text {
                        width: fileColumn.width
                        visible: !dialog.isSaveDialog && filesOnlyModel.count === 0
                        text: qsTr("No files in this folder")
                        font.pixelSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        font.italic: true
                        color: Style.textDescriptionColor
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: 20
                    }

                    // Message for save dialogs - shown instead of file list
                    Text {
                        width: fileColumn.width
                        visible: dialog.isSaveDialog
                        text: qsTr("Navigate to a folder using the panel on the left,\nor type a path in the address bar above.")
                        font.pixelSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        font.italic: true
                        color: Style.textDescriptionColor
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        topPadding: 40
                    }
                }
            }
        }
    }

    // Buttons
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: Style.spacingMedium
        Item { Layout.fillWidth: true }
        ImButton {
            id: cancelButton
            text: CommonStrings.cancel
            activeFocusOnTab: true
            onClicked: { dialog.close(); dialog.rejected() }
        }
        ImButton {
            id: openButton
            text: dialog.isSaveDialog ? qsTr("Save") : qsTr("Open")
            enabled: dialog.isSaveDialog
                ? String(dialog._currentFilename).trim().length > 0
                : String(dialog.selectedFile).length > 0
            activeFocusOnTab: true
            onClicked: {
                if (dialog.isSaveDialog) {
                    dialog.selectedFile = dialog._toFileUrl(dialog._buildFilePath())
                }
                // Save current folder for next time
                if (dialog.isSaveDialog) {
                    dialogSettings.lastSaveFolder = String(dialog.currentFolder)
                } else {
                    dialogSettings.lastOpenFolder = String(dialog.currentFolder)
                }
                dialog.close()
                dialog.accepted()
            }
        }
    }
}



