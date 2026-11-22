import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects

ApplicationWindow {
    id: win
    width: 1080
    height: 680
    minimumWidth: 1000
    minimumHeight: 480
    property bool startVisible: true
    property bool vizOn: true
    property bool galleryMode: false
    property bool libraryMode: false        // LIBRARY tab: all songs of the music folder
    property bool albumPage: false          // the big album page (opened from the gallery) is shown
    property real cardSize: 170
    visible: startVisible
    title: "CyberNeon Player"
    color: "#0A0710"

    readonly property color panel: "#14091F"
    readonly property color card: "#1C1030"
    readonly property color edge: "#3B1F6B"
    readonly property color violet: "#B04CFF"
    readonly property color magenta: "#FF2BD6"
    readonly property color cyan: "#00F0FF"
    readonly property color fg: "#EDE6FF"
    readonly property color dim: "#8C7FAD"
    readonly property var sortNames: ["ALBUM A-Z", "ARTIST", "YEAR", "MY ORDER"]

    // the selected album is remembered by id, so it stays selected when the list changes
    property string selectedId: ""
    readonly property int selectedIndex: {
        var a = backend.albums
        for (var i = 0; i < a.length; i++)
            if (a[i].id === selectedId) return i
        return a.length > 0 ? 0 : -1
    }
    readonly property var albumData: selectedIndex >= 0 ? backend.albums[selectedIndex] : null
    readonly property bool isMine: albumData !== null && albumData.custom === true
    readonly property var customAlbums: backend.albums.filter(function (a) { return a.custom })

    function fmt(ms) {
        var s = Math.max(0, Math.floor(ms / 1000))
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    function albumLength(a) {
        var s = 0
        for (var i = 0; i < a.tracks.length; i++) s += a.tracks[i].length
        return fmt(s * 1000)
    }
    function coverOf(a) {
        return a.coverUrl !== "" ? a.coverUrl : "image://cover/" + a.cover + "?v=" + backend.version
    }

    Shortcut { sequence: "Space"; onActivated: backend.togglePlay() }
    Shortcut { sequence: "Escape"; enabled: win.albumPage; onActivated: gallery.closePage() }
    Connections {
        target: backend
        function onAlbumsChanged() {
            if (!win.albumPage) return
            var a = backend.albums
            for (var i = 0; i < a.length; i++)
                if (a[i].id === win.selectedId) return
            gallery.closeNow()                      // the album is gone (hidden, deleted, auto albums switched)
        }
    }

    // analyse audio only while the window is visible (no CPU use in the tray)
    function updateViz() { viz.setActive(win.visible && (win.vizOn || win.albumPage)) }
    onVisibleChanged: updateViz()
    onVizOnChanged: updateViz()
    onAlbumPageChanged: updateViz()
    Component.onCompleted: updateViz()

    // ================= dialogs =================
    FolderDialog {
        id: folderDialog
        title: "Choose your music folder"
        onAccepted: backend.setFolder(selectedFolder.toString())
    }
    FileDialog {
        id: coverDialog
        title: "Choose album picture"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
        onAccepted: if (win.isMine) backend.setCover(win.albumData.id, selectedFile.toString())
    }
    FileDialog {
        id: filesDialog
        title: "Add songs to the album"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Audio and CD images (*.mp3 *.flac *.ogg *.opus *.m4a *.wav *.ape *.wv *.cue)"]
        currentFolder: "file://" + backend.folder
        onAccepted: {
            var list = []
            for (var i = 0; i < selectedFiles.length; i++) list.push(selectedFiles[i].toString())
            backend.addFiles(win.albumData.id, list)
        }
    }

    FileDialog {
        id: m3uSave
        title: "Export album as playlist"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "m3u8"
        nameFilters: ["Playlist (*.m3u *.m3u8)"]
        onAccepted: if (win.albumData) backend.exportM3U(win.albumData.id, selectedFile.toString())
    }
    FileDialog {
        id: m3uOpen
        title: "Import playlist"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Playlist (*.m3u *.m3u8)"]
        currentFolder: "file://" + backend.folder
        onAccepted: {
            var id = backend.importM3U(selectedFile.toString())
            if (id !== "") { win.selectedId = id; win.libraryMode = false }
        }
    }

    // drag songs or whole folders from the file manager into the window
    DropArea {
        id: dropArea
        anchors.fill: parent
        z: 1000
        keys: ["text/uri-list"]
        onDropped: function (drop) {
            if (drop.hasUrls) {
                var list = []
                for (var i = 0; i < drop.urls.length; i++) list.push(drop.urls[i].toString())
                var id = backend.addDropped(win.albumData ? win.albumData.id : "", list)
                drop.acceptProposedAction()
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: dropArea.containsDrag
            color: "#CC0A0710"
            border.color: win.magenta
            border.width: 3
            Column {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "DROP TO ADD"
                    color: win.magenta
                    font.family: "monospace"
                    font.pixelSize: 34
                    font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "songs or folders  >  " + (win.albumData ? win.albumData.name : "Playlist")
                    color: win.cyan
                    font.family: "monospace"
                    font.pixelSize: 16
                }
            }
        }
    }

    // create / edit album
    Popup {
        id: albumDialog
        property string editId: ""
        modal: true
        focus: true
        padding: 18
        width: 380
        height: 306
        x: Math.round((win.width - width) / 2)
        y: Math.round((win.height - height) / 2)
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: "#B0000000" }
        background: Rectangle { color: win.panel; border.color: win.magenta; border.width: 1 }

        function openNew() {
            editId = ""
            nameField.text = ""
            artistField.text = ""
            yearField.text = ""
            open()
            nameField.forceActiveFocus()
        }
        function openEdit(a) {
            editId = a.id
            nameField.text = a.name
            artistField.text = a.artist
            yearField.text = a.year > 0 ? String(a.year) : ""
            open()
            nameField.forceActiveFocus()
        }
        function save() {
            var y = parseInt(yearField.text)
            if (isNaN(y)) y = 0
            if (editId === "") {
                win.selectedId = backend.createAlbum(nameField.text, artistField.text, y)
                Qt.callLater(function () { albumList.positionViewAtIndex(win.selectedIndex, ListView.Contain) })
            } else {
                backend.editAlbum(editId, nameField.text, artistField.text, y)
            }
            close()
        }

        contentItem: ColumnLayout {
            spacing: 10
            Text {
                text: albumDialog.editId === "" ? "NEW ALBUM" : "EDIT ALBUM"
                color: win.magenta
                font.family: "monospace"
                font.bold: true
                font.pixelSize: 16
            }
            NeonField { id: nameField; Layout.fillWidth: true; placeholderText: "Album name"; onAccepted: albumDialog.save() }
            NeonField { id: artistField; Layout.fillWidth: true; placeholderText: "Artist (optional)"; onAccepted: albumDialog.save() }
            NeonField {
                id: yearField
                Layout.fillWidth: true
                placeholderText: "Year (optional), e.g. 2024"
                validator: IntValidator { bottom: 0; top: 9999 }
                inputMethodHints: Qt.ImhDigitsOnly
                onAccepted: albumDialog.save()
            }
            Text {
                Layout.fillWidth: true
                visible: albumDialog.editId.indexOf("t:") === 0
                text: "Applies inside this player only. Leave all fields empty to restore the original. Artist \"-\" means no artist."
                color: win.dim
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                NeonButton { text: "CANCEL"; accent: win.dim; implicitWidth: 90; onClicked: albumDialog.close() }
                NeonButton { text: "SAVE"; accent: win.cyan; implicitWidth: 90; onClicked: albumDialog.save() }
            }
        }
    }

    // edit song title / artist
    Popup {
        id: trackDialog
        property int trackIdx: -1
        modal: true
        focus: true
        padding: 18
        width: 420
        height: 290
        x: Math.round((win.width - width) / 2)
        y: Math.round((win.height - height) / 2)
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: "#B0000000" }
        background: Rectangle { color: win.panel; border.color: win.violet; border.width: 1 }

        function openFor(t) {
            trackIdx = t.idx
            tTitle.text = t.title
            tArtist.text = t.artist
            open()
            tTitle.forceActiveFocus()
        }
        function save() {
            backend.editTrack(trackIdx, tTitle.text, tArtist.text)
            close()
        }

        contentItem: ColumnLayout {
            spacing: 10
            Text {
                text: "EDIT SONG"
                color: win.violet
                font.family: "monospace"
                font.bold: true
                font.pixelSize: 16
            }
            NeonField { id: tTitle; Layout.fillWidth: true; placeholderText: "Title"; onAccepted: trackDialog.save() }
            NeonField { id: tArtist; Layout.fillWidth: true; placeholderText: "Artist"; onAccepted: trackDialog.save() }
            Text {
                Layout.fillWidth: true
                text: "Changes apply inside this player only; the music file is not modified. An empty field restores the original tag."
                color: win.dim
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                NeonButton {
                    text: "RESET"
                    accent: win.magenta
                    implicitWidth: 80
                    onClicked: { backend.resetTrack(trackDialog.trackIdx); trackDialog.close() }
                }
                Item { Layout.fillWidth: true }
                NeonButton { text: "CANCEL"; accent: win.dim; implicitWidth: 90; onClicked: trackDialog.close() }
                NeonButton { text: "SAVE"; accent: win.cyan; implicitWidth: 90; onClicked: trackDialog.save() }
            }
        }
    }

    // hidden albums: restore them
    Popup {
        id: hiddenPopup
        modal: true
        focus: true
        padding: 22
        width: Math.min(win.width - 60, 640)
        height: Math.min(win.height - 60, Math.max(300, 210 + backend.hiddenAlbums.length * 60))
        x: Math.round((win.width - width) / 2)
        y: Math.round((win.height - height) / 2)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: "#B0000000" }
        background: Rectangle { color: win.panel; border.color: win.dim; border.width: 1 }
        onOpened: if (backend.hiddenAlbums.length === 0) close()
        contentItem: ColumnLayout {
            spacing: 12
            Text {
                text: "HIDDEN ALBUMS (" + backend.hiddenAlbums.length + ")"
                color: win.cyan
                font.family: "monospace"
                font.bold: true
                font.pixelSize: 20
            }
            Text {
                Layout.fillWidth: true
                text: "Hidden albums are only removed from the player. The music files are not touched."
                color: win.dim
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.edge }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: backend.hiddenAlbums
                ScrollBar.vertical: ScrollBar {
                    contentItem: Rectangle { implicitWidth: 6; color: win.violet; opacity: 0.7 }
                }
                delegate: Item {
                    width: ListView.view.width
                    height: 56
                    Rectangle {
                        anchors.fill: parent
                        color: hrow.hovered ? win.card : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    HoverHandler { id: hrow }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 14
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { Layout.fillWidth: true; text: modelData.name; color: win.fg; font.bold: true; font.pixelSize: 15; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: modelData.artist; color: win.dim; font.pixelSize: 12; elide: Text.ElideRight }
                        }
                        NeonButton {
                            text: "RESTORE"
                            accent: win.cyan
                            fontSize: 14
                            implicitWidth: 130
                            implicitHeight: 40
                            onClicked: backend.unhideAlbum(modelData.id)
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.edge }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                NeonButton {
                    text: "RESTORE ALL"
                    accent: win.cyan
                    fontSize: 14
                    implicitWidth: 160
                    implicitHeight: 40
                    onClicked: { backend.unhideAll(); hiddenPopup.close() }
                }
                Item { Layout.fillWidth: true }
                NeonButton { text: "CLOSE"; accent: win.dim; fontSize: 14; implicitWidth: 110; implicitHeight: 40; onClicked: hiddenPopup.close() }
            }
        }
    }

    // delete album
    Popup {
        id: deleteDialog
        modal: true
        focus: true
        padding: 18
        width: 360
        height: 160
        x: Math.round((win.width - width) / 2)
        y: Math.round((win.height - height) / 2)
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: "#B0000000" }
        background: Rectangle { color: win.panel; border.color: win.magenta; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: 10
            Text {
                Layout.fillWidth: true
                text: "Delete album \"" + (win.albumData ? win.albumData.name : "") + "\"?\nThe songs themselves are not deleted."
                color: win.fg
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                NeonButton { text: "CANCEL"; accent: win.dim; implicitWidth: 90; onClicked: deleteDialog.close() }
                NeonButton {
                    text: "DELETE"
                    accent: win.magenta
                    implicitWidth: 90
                    onClicked: {
                        if (win.isMine) backend.deleteAlbum(win.albumData.id)
                        deleteDialog.close()
                        gallery.closeNow()
                    }
                }
            }
        }
    }

    // "add this song to one of my albums"
    Popup {
        id: addPopup
        property int trackIdx: -1
        modal: true
        focus: true
        padding: 16
        width: 340
        height: Math.min(440, 130 + Math.max(1, Math.min(backend.albums.length, 8)) * 42)
        x: Math.round((win.width - width) / 2)
        y: Math.round((win.height - height) / 2)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: "#B0000000" }
        background: Rectangle { color: win.panel; border.color: win.cyan; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: 8
            Text {
                text: "ADD TO ALBUM"
                color: win.cyan
                font.family: "monospace"
                font.bold: true
                font.pixelSize: 16
            }
            Text {
                visible: backend.albums.length === 0
                Layout.fillWidth: true
                text: "There are no albums yet. Create one with NEW ALBUM."
                color: win.dim
                wrapMode: Text.WordWrap
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: backend.albums
                delegate: Item {
                    width: ListView.view.width
                    height: 42
                    Rectangle { anchors.fill: parent; color: apm.containsMouse ? win.card : "transparent" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        text: (modelData.custom ? "\u2605 " : "") + modelData.name + "  (" + modelData.tracks.length + ")"
                        color: win.fg
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: apm
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            backend.addTrack(modelData.id, addPopup.trackIdx)
                            addPopup.close()
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                NeonButton {
                    text: "NEW ALBUM"
                    accent: win.magenta
                    implicitWidth: 110
                    onClicked: { addPopup.close(); albumDialog.openNew() }
                }
                Item { Layout.fillWidth: true }
                NeonButton { text: "CLOSE"; accent: win.dim; implicitWidth: 80; onClicked: addPopup.close() }
            }
        }
    }

    // one song row (used by the list view and by the album page)
    Component {
        id: songRow
        Item {
                            id: trow
                            width: ListView.view.width
                            height: 40
                            z: dh.active ? 10 : 0
                            readonly property bool cur: backend.currentIndex === modelData.idx
                            property bool editing: false
                            // while a button of this row is hovered the whole row lights up in that button's colour
                            readonly property bool onBtn: edBtn.hovered || addBtn.hovered || delBtn.hovered
                            readonly property color hot: delBtn.hovered ? win.magenta : (addBtn.hovered ? win.cyan : win.violet)

                            HoverHandler { id: rowHover }

                            // line that shows where the dragged song will land
                            Rectangle {
                                visible: dh.active && drop.to !== index
                                width: parent.width
                                height: 2
                                color: win.magenta
                                y: (drop.to > index ? (drop.to - index + 1) : (drop.to - index)) * trow.height - 1
                            }
                            QtObject {
                                id: drop
                                readonly property int to: Math.max(0, Math.min(trow.ListView.view.count - 1, index + Math.round(content.y / trow.height)))
                            }

                            Item {
                                id: content
                                width: trow.width
                                height: trow.height
                                opacity: dh.active ? 0.85 : 1.0
                                Behavior on y { enabled: !dh.active; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    anchors.fill: parent
                                    color: trow.onBtn ? Qt.rgba(trow.hot.r, trow.hot.g, trow.hot.b, 0.22)
                                           : (dh.active ? win.card : (cur ? win.card : (rowHover.hovered ? win.panel : "transparent")))
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                                Rectangle {
                                    width: 3
                                    height: parent.height
                                    color: trow.onBtn ? trow.hot : (cur ? win.cyan : "transparent")
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onDoubleClicked: backend.playAlbum(win.selectedIndex, index)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    // drag handle
                                    Item {
                                        Layout.preferredWidth: 22
                                        Layout.fillHeight: true
                                        Text {
                                            anchors.centerIn: parent
                                            text: "::"
                                            color: (dh.active || rowHover.hovered) ? win.magenta : win.edge
                                            font.family: "monospace"
                                            font.bold: true
                                            font.pixelSize: 14
                                        }
                                        DragHandler {
                                            id: dh
                                            target: content
                                            xAxis.enabled: false
                                            yAxis.enabled: true
                                            cursorShape: Qt.ClosedHandCursor
                                            onActiveChanged: {
                                                trow.ListView.view.dragging = active
                                                if (!active) {
                                                    var to = drop.to
                                                    content.y = 0
                                                    if (to !== index)
                                                        backend.moveTrack(win.albumData.id, modelData.idx, to + 1)
                                                }
                                            }
                                        }
                                        HoverHandler { cursorShape: Qt.OpenHandCursor }
                                    }

                                    // track number (click to type a position)
                                    Item {
                                        Layout.preferredWidth: 32
                                        Layout.fillHeight: true
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !trow.editing
                                            text: modelData.no > 0 ? modelData.no : (index + 1)
                                            color: cur ? win.cyan : win.dim
                                            font.family: "monospace"
                                        }
                                        TextInput {
                                            id: numInput
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 30
                                            visible: trow.editing
                                            color: win.fg
                                            font.family: "monospace"
                                            selectByMouse: true
                                            validator: IntValidator { bottom: 1; top: 9999 }
                                            onAccepted: {
                                                if (text !== "")
                                                    backend.moveTrack(win.albumData.id, modelData.idx, parseInt(text))
                                                trow.editing = false
                                            }
                                            onActiveFocusChanged: if (!activeFocus) trow.editing = false
                                            Keys.onEscapePressed: trow.editing = false
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !trow.editing
                                            cursorShape: Qt.IBeamCursor
                                            onClicked: {
                                                numInput.text = String(modelData.no)
                                                trow.editing = true
                                                numInput.forceActiveFocus()
                                                numInput.selectAll()
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        color: cur ? win.cyan : win.fg
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: win.fmt(modelData.length * 1000)
                                        color: win.dim
                                        font.family: "monospace"
                                    }
                                    NeonButton {
                                        id: edBtn
                                        text: "ED"
                                        accent: win.violet
                                        implicitWidth: 32
                                        implicitHeight: 26
                                        onClicked: trackDialog.openFor(modelData)
                                    }
                                    NeonButton {
                                        id: addBtn
                                        text: "+"
                                        accent: win.cyan
                                        implicitWidth: 28
                                        implicitHeight: 26
                                        onClicked: { addPopup.trackIdx = modelData.idx; addPopup.open() }
                                    }
                                    NeonButton {
                                        id: delBtn
                                        text: "x"
                                        accent: win.magenta
                                        implicitWidth: 28
                                        implicitHeight: 26
                                        onClicked: backend.removeTrack(win.albumData.id, modelData.idx)
                                    }
                                }
                            }
                        }
    }

    // ================= main layout =================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------- header ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: win.panel
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                Text {
                    text: "CYBERNEON // PLAYER"
                    color: win.magenta
                    font.family: "monospace"
                    font.bold: true
                    font.pixelSize: 18
                }
                Text {
                    visible: backend.note !== ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: 420
                    text: backend.note
                    color: win.magenta
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: backend.scanning ? "SCANNING..." : (backend.trackCount + " TRACKS")
                    color: win.dim
                    font.family: "monospace"
                    font.pixelSize: 12
                }
                NeonButton {
                    text: "VIZ"
                    accent: win.cyan
                    active: win.vizOn
                    implicitWidth: 56
                    onClicked: win.vizOn = !win.vizOn
                }
                NeonButton {
                    text: "NEW ALBUM"
                    accent: win.magenta
                    implicitWidth: 110
                    onClicked: albumDialog.openNew()
                }
                NeonButton {
                    text: "IMPORT M3U"
                    accent: win.violet
                    implicitWidth: 110
                    onClicked: m3uOpen.open()
                }
                NeonButton {
                    text: "NOTIFY: " + (backend.notifications ? "ON" : "OFF")
                    accent: win.cyan
                    active: backend.notifications
                    implicitWidth: 112
                    onClicked: backend.toggleNotifications()
                }
                NeonButton {
                    text: "SORT: " + win.sortNames[backend.sortMode]
                    accent: win.violet
                    implicitWidth: 150
                    onClicked: backend.toggleSort()
                }
                NeonButton {
                    text: "FOLDER"
                    accent: win.cyan
                    implicitWidth: 90
                    onClicked: folderDialog.open()
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.violet }

        // ---------- tabs: LIST / GALLERY ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            color: "#0D0814"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 16
                spacing: 8
                NeonButton { text: "LIST"; accent: win.cyan; active: !win.galleryMode; implicitWidth: 70; implicitHeight: 28; onClicked: { gallery.closeNow(); win.libraryMode = false; win.galleryMode = false } }
                NeonButton { text: "GALLERY"; accent: win.cyan; active: win.galleryMode; implicitWidth: 100; implicitHeight: 28; onClicked: { if (win.galleryMode && win.albumPage) gallery.closePage(); win.libraryMode = false; win.galleryMode = true } }
                NeonButton { text: "LIBRARY"; accent: win.cyan; active: win.libraryMode; implicitWidth: 100; implicitHeight: 28; onClicked: { gallery.closeNow(); win.galleryMode = false; win.libraryMode = true } }
                NeonButton {
                    visible: backend.hiddenAlbums.length > 0
                    text: "HIDDEN (" + backend.hiddenAlbums.length + ")"
                    accent: win.dim
                    implicitWidth: 110
                    implicitHeight: 28
                    onClicked: hiddenPopup.open()
                }
                NeonButton {
                    text: "AUTO ALBUMS: " + (backend.autoAlbums ? "ON" : "OFF")
                    accent: win.violet
                    active: backend.autoAlbums
                    implicitWidth: 170
                    implicitHeight: 28
                    onClicked: backend.toggleAutoAlbums()
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: win.galleryMode
                    text: backend.albums.length + " ALBUMS"
                    color: win.dim
                    font.family: "monospace"
                    font.pixelSize: 12
                }
                Text {
                    visible: win.galleryMode
                    text: "SIZE"
                    color: win.dim
                    font.family: "monospace"
                    font.pixelSize: 12
                }
                NeonSlider {
                    visible: win.galleryMode
                    Layout.preferredWidth: 160
                    accent: win.violet
                    from: 110
                    to: 260
                    value: win.cardSize
                    onMoved: win.cardSize = value
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.edge }

        // ---------- albums + tracks ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            visible: !win.galleryMode && !win.libraryMode

            // albums
            Rectangle {
                Layout.preferredWidth: 340
                Layout.fillHeight: true
                color: "#0D0814"
                ListView {
                    id: albumList
                    anchors.fill: parent
                    clip: true
                    property bool dragging: false
                    interactive: !dragging
                    model: backend.albums
                    ScrollBar.vertical: ScrollBar {
                        contentItem: Rectangle { implicitWidth: 6; color: win.violet; opacity: 0.7 }
                    }
                    delegate: Item {
                        id: arow
                        width: ListView.view.width
                        height: 72
                        z: adh.active ? 10 : 0
                        readonly property bool sel: index === win.selectedIndex
                        HoverHandler { id: arowHover }

                        QtObject {
                            id: adrop
                            readonly property int to: Math.max(0, Math.min(arow.ListView.view.count - 1, index + Math.round(amover.y / arow.height)))
                        }
                        // line that shows where the dragged album will land
                        Rectangle {
                            visible: adh.active && adrop.to !== index
                            width: parent.width
                            height: 2
                            color: win.magenta
                            y: (adrop.to > index ? (adrop.to - index + 1) : (adrop.to - index)) * arow.height - 1
                        }

                        Item {
                            id: amover
                            width: arow.width
                            height: arow.height
                            opacity: adh.active ? 0.85 : 1.0
                            Behavior on y { enabled: !adh.active; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Rectangle {
                                anchors.fill: parent
                                color: (sel || adh.active) ? win.card : (arowHover.hovered ? win.panel : "transparent")
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Rectangle { width: 3; height: parent.height; color: sel ? win.magenta : "transparent" }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: win.selectedId = modelData.id
                                onDoubleClicked: backend.playAlbum(index, 0)
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 10
                                spacing: 8
                                // drag handle: drag the album to put it where you want
                                Item {
                                    Layout.preferredWidth: 20
                                    Layout.fillHeight: true
                                    Text {
                                        anchors.centerIn: parent
                                        text: "::"
                                        color: (adh.active || arowHover.hovered) ? win.magenta : win.edge
                                        font.family: "monospace"
                                        font.bold: true
                                        font.pixelSize: 14
                                    }
                                    DragHandler {
                                        id: adh
                                        target: amover
                                        xAxis.enabled: false
                                        yAxis.enabled: true
                                        cursorShape: Qt.ClosedHandCursor
                                        onActiveChanged: {
                                            albumList.dragging = active
                                            if (!active) {
                                                var to = adrop.to
                                                amover.y = 0
                                                if (to !== index)
                                                    backend.moveAlbum(modelData.id, to)
                                            }
                                        }
                                    }
                                    HoverHandler { cursorShape: Qt.OpenHandCursor }
                                }
                                Image {
                                    Layout.preferredWidth: 54
                                    Layout.preferredHeight: 54
                                    source: win.coverOf(modelData)
                                    sourceSize: Qt.size(108, 108)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: (modelData.custom ? "\u2605 " : "") + modelData.name
                                        color: sel ? win.magenta : win.fg
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.artist + (modelData.year > 0 ? "  \u00b7  " + modelData.year : "")
                                              + (modelData.custom ? "  \u00b7  " + modelData.tracks.length + " tracks" : "")
                                        color: win.dim
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: backend.albums.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    color: win.dim
                    font.family: "monospace"
                    text: backend.scanning ? "SCANNING..." : "No music found in\n" + backend.folder
                }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: win.edge }

            // tracks of the selected album
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(128, headerCol.implicitHeight + 28)
                    color: win.panel
                    visible: win.albumData !== null
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 16
                        Image {
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 100
                            Layout.alignment: Qt.AlignTop
                            source: win.albumData ? win.coverOf(win.albumData) : ""
                            sourceSize: Qt.size(200, 200)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        ColumnLayout {
                            id: headerCol
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 4
                            Text {
                                Layout.fillWidth: true
                                text: win.albumData ? (win.isMine ? "\u2605 " : "") + win.albumData.name : ""
                                color: win.fg
                                font.bold: true
                                font.pixelSize: 22
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: win.albumData ? win.albumData.artist + (win.albumData.year > 0 ? "  \u00b7  " + win.albumData.year : "") : ""
                                color: win.dim
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Drag a song by its :: handle to reorder, or click its number to type a position."
                                color: win.dim
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                NeonButton { text: "PLAY"; accent: win.cyan; implicitWidth: 64; onClicked: backend.playAlbum(win.selectedIndex, 0) }
                                NeonButton { text: "PLAY ALL"; accent: win.violet; implicitWidth: 88; onClicked: backend.playLibrary() }
                                NeonButton { text: "EDIT"; accent: win.magenta; implicitWidth: 60; onClicked: albumDialog.openEdit(win.albumData) }
                                NeonButton { visible: win.isMine; text: "COVER"; accent: win.magenta; implicitWidth: 70; onClicked: coverDialog.open() }
                                NeonButton { text: "+ FILES"; accent: win.magenta; implicitWidth: 80; onClicked: filesDialog.open() }
                                NeonButton { text: "EXPORT M3U"; accent: win.violet; implicitWidth: 104; onClicked: m3uSave.open() }
                                NeonButton { visible: win.isMine; text: "DELETE"; accent: win.dim; implicitWidth: 72; onClicked: deleteDialog.open() }
                                NeonButton { visible: !win.isMine; text: "HIDE"; accent: win.dim; implicitWidth: 60; onClicked: backend.hideAlbum(win.albumData.id) }
                            }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.edge }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: trackList
                        anchors.fill: parent
                        clip: true
                        property bool dragging: false
                        interactive: !dragging
                        model: win.albumData ? win.albumData.tracks : []
                        ScrollBar.vertical: ScrollBar {
                            contentItem: Rectangle { implicitWidth: 6; color: win.violet; opacity: 0.7 }
                        }
                        delegate: songRow
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: win.albumData !== null && win.albumData.tracks.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        color: win.dim
                        font.family: "monospace"
                        text: "Empty album.\nUse + FILES, or the + button on any song."
                    }
                }

                // ---------- neon visualizer ----------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: win.vizOn ? 92 : 0
                    visible: win.vizOn
                    color: "#0D0814"
                    Rectangle { width: parent.width; height: 1; color: win.edge }
                    Row {
                        id: barsRow
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 3
                        Repeater {
                            model: 40
                            Item {
                                width: (barsRow.width - 39 * barsRow.spacing) / 40
                                height: barsRow.height
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, (viz.bars[index] || 0) * parent.height)
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: win.magenta }
                                        GradientStop { position: 1.0; color: win.cyan }
                                    }
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 2
                                    color: "#FFFFFF"
                                    opacity: 0.75
                                    y: parent.height - Math.max(2, (viz.peaks[index] || 0) * parent.height) - 3
                                }
                            }
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        text: viz.mode === "live" ? "LIVE" : "SIM"
                        color: win.dim
                        font.family: "monospace"
                        font.pixelSize: 9
                    }
                }
            }
        }

        // ---------- gallery: all albums as covers ----------
        Item {
            id: gallery
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: win.galleryMode
            clip: true

            GridView {
                id: grid
                anchors.fill: parent
                anchors.margins: 8
                property bool dragging: false
                property int dropIdx: -1
                interactive: !dragging
                model: backend.albums
                readonly property int cols: Math.max(1, Math.floor(width / (win.cardSize + 24)))
                cellWidth: Math.floor(width / cols)
                cellHeight: cellWidth + 60
                ScrollBar.vertical: ScrollBar {
                    contentItem: Rectangle { implicitWidth: 6; color: win.violet; opacity: 0.7 }
                }
                Rectangle {
                    visible: grid.dropIdx >= 0
                    x: (grid.dropIdx % grid.cols) * grid.cellWidth + 6
                    y: Math.floor(grid.dropIdx / grid.cols) * grid.cellHeight + 6
                    width: grid.cellWidth - 12
                    height: grid.cellHeight - 12
                    color: "transparent"
                    border.color: win.magenta
                    border.width: 2
                    z: 1
                }

                delegate: Item {
                    id: cell
                    width: grid.cellWidth
                    height: grid.cellHeight
                    z: gdh.active ? 100 : (hh.hovered ? 2 : 0)

                    // pointer position inside the cell, -1 .. 1 (0 when not hovered or while dragging)
                    readonly property real nx: (hh.hovered && !gdh.active) ? Math.max(-1, Math.min(1, (hh.point.position.x / width - 0.5) * 2)) : 0
                    readonly property real ny: (hh.hovered && !gdh.active) ? Math.max(-1, Math.min(1, (hh.point.position.y / height - 0.5) * 2)) : 0
                    // 3D tilt: the corner under the pointer is pressed away from you
                    property real tiltY: nx * 14
                    property real tiltX: -ny * 14
                    Behavior on tiltY { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                    Behavior on tiltX { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

                    // the card (and its glow) moves as one piece while you drag it
                    Item {
                        id: mover
                        width: cell.width
                        height: cell.height
                        opacity: gdh.active ? 0.8 : 1.0
                        Behavior on x { enabled: !gdh.active; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on y { enabled: !gdh.active; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        // neon glow plate behind the card, shifts against the tilt (fake depth / shadow)
                        Rectangle {
                            x: 10 - cell.nx * 12
                            y: 10 - cell.ny * 12
                            width: cell.width - 20
                            height: cell.height - 20
                            color: win.magenta
                            opacity: hh.hovered ? 0.22 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }

                        Rectangle {
                            id: cardRect
                            anchors.fill: parent
                            anchors.margins: 10
                            clip: true
                            color: hh.hovered ? win.card : win.panel
                            border.width: 1
                            border.color: hh.hovered ? win.magenta : win.edge
                            scale: hh.hovered ? 1.06 : 1.0
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Behavior on border.color { ColorAnimation { duration: 140 } }
                            transform: [
                                Rotation {
                                    origin.x: cardRect.width / 2
                                    origin.y: cardRect.height / 2
                                    axis { x: 1; y: 0; z: 0 }
                                    angle: cell.tiltX
                                },
                                Rotation {
                                    origin.x: cardRect.width / 2
                                    origin.y: cardRect.height / 2
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: cell.tiltY
                                }
                            ]

                            // click = open the album with its song list
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var p = coverBox.mapToItem(gallery, 0, 0)       // where the card's cover is right now
                                    win.selectedId = modelData.id
                                    gallery.openPage(p.x, p.y, coverBox.width, coverBox.height, win.coverOf(modelData))
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                Item {
                                    id: coverBox
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width
                                    clip: true
                                    // the picture is a bit larger than its frame and slides against the tilt: parallax
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: -10
                                        source: win.coverOf(modelData)
                                        sourceSize: Qt.size(400, 400)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        opacity: hh.hovered ? 1.0 : 0.88
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                        transform: Translate {
                                            x: -cell.nx * 8
                                            y: -cell.ny * 8
                                            Behavior on x { NumberAnimation { duration: 90 } }
                                            Behavior on y { NumberAnimation { duration: 90 } }
                                        }
                                    }
                                    // light spot that follows the pointer
                                    Rectangle {
                                        width: coverBox.width * 0.9
                                        height: width
                                        radius: width / 2
                                        x: (cell.nx * 0.5 + 0.5) * coverBox.width - width / 2
                                        y: (cell.ny * 0.5 + 0.5) * coverBox.height - height / 2
                                        color: "#FFFFFF"
                                        opacity: hh.hovered ? 0.12 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                    }
                                    // remove: folder albums are hidden (undo via HIDDEN), your own albums are deleted
                                    NeonButton {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: 8
                                        text: modelData.custom ? "DEL" : "HIDE"
                                        accent: win.dim
                                        implicitWidth: 48
                                        implicitHeight: 26
                                        fontSize: 11
                                        opacity: hh.hovered ? 1.0 : 0.0
                                        visible: opacity > 0
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                        onClicked: {
                                            if (modelData.custom) { win.selectedId = modelData.id; deleteDialog.open() }
                                            else backend.hideAlbum(modelData.id)
                                        }
                                    }
                                    // quick play button, appears on hover
                                    NeonButton {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 8
                                        text: ">"
                                        accent: win.magenta
                                        implicitWidth: 42
                                        implicitHeight: 34
                                        fontSize: 15
                                        opacity: hh.hovered ? 1.0 : 0.0
                                        visible: opacity > 0
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                        onClicked: backend.playAlbum(index, 0)
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        color: hh.hovered ? win.magenta : win.fg
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.artist
                                        color: win.dim
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: modelData.year > 0
                                        text: modelData.year
                                        color: win.violet
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }

                    // where the dragged card would land (grid slot under its centre)
                    readonly property int dropTo: {
                        var cx = cell.x + mover.x + mover.width / 2
                        var cy = cell.y + mover.y + mover.height / 2
                        var col = Math.max(0, Math.min(grid.cols - 1, Math.floor(cx / grid.cellWidth)))
                        var row = Math.max(0, Math.floor(cy / grid.cellHeight))
                        return Math.max(0, Math.min(grid.count - 1, row * grid.cols + col))
                    }
                    Binding { target: grid; property: "dropIdx"; value: cell.dropTo; when: gdh.active }
                    DragHandler {
                        id: gdh
                        target: mover
                        cursorShape: Qt.ClosedHandCursor
                        onActiveChanged: {
                            grid.dragging = active
                            if (!active) {
                                var to = cell.dropTo
                                mover.x = 0
                                mover.y = 0
                                grid.dropIdx = -1
                                if (to !== index)
                                    backend.moveAlbum(modelData.id, to)
                            }
                        }
                    }

                    // hover is tracked on the fixed cell (not the scaled card), so the zoom cannot make it flicker
                    HoverHandler { id: hh }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: backend.albums.length === 0
                horizontalAlignment: Text.AlignHCenter
                color: win.dim
                font.family: "monospace"
                text: backend.scanning ? "SCANNING..." : "No albums yet"
            }

            // ===== state and animation of the album page =====
            property real ox: 0
            property real oy: 0
            property real ow: 100
            property real oh: 100
            property real tx: 0
            property real ty: 0
            property real tw: 100
            property real th: 100
            property string heroSrc: ""

            function openPage(x, y, w, h, src) {
                closeAnim.stop()
                ox = x; oy = y; ow = w; oh = h
                heroSrc = src
                win.albumPage = true
                Qt.callLater(function () {              // wait one frame: the page must be laid out first
                    var p = pageCover.mapToItem(gallery, 0, 0)
                    tx = p.x; ty = p.y; tw = pageCover.width; th = pageCover.height
                    openAnim.restart()
                })
            }
            function closePage() {
                if (!win.albumPage) return
                openAnim.stop()
                var p = pageCover.mapToItem(gallery, 0, 0)
                tx = p.x; ty = p.y; tw = pageCover.width; th = pageCover.height
                closeAnim.restart()
            }
            function closeNow() {
                openAnim.stop()
                closeAnim.stop()
                hero.visible = false
                pageCover.opacity = 1
                albumPageItem.opacity = 0
                win.albumPage = false
            }

            // the cover that flies between the gallery card and the album page
            Image {
                id: hero
                visible: false
                z: 20
                source: gallery.heroSrc
                sourceSize: Qt.size(400, 400)
                fillMode: Image.PreserveAspectCrop
            }

            SequentialAnimation {
                id: openAnim
                ScriptAction { script: { hero.visible = true; pageCover.opacity = 0 } }
                ParallelAnimation {
                    NumberAnimation { target: hero; property: "x"; from: gallery.ox; to: gallery.tx; duration: 440; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hero; property: "y"; from: gallery.oy; to: gallery.ty; duration: 440; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hero; property: "width"; from: gallery.ow; to: gallery.tw; duration: 440; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hero; property: "height"; from: gallery.oh; to: gallery.th; duration: 440; easing.type: Easing.OutCubic }
                    NumberAnimation { target: albumPageItem; property: "opacity"; from: 0; to: 1; duration: 360 }
                }
                ScriptAction { script: { hero.visible = false; pageCover.opacity = 1 } }
            }
            SequentialAnimation {
                id: closeAnim
                ScriptAction { script: { hero.visible = true; pageCover.opacity = 0 } }
                ParallelAnimation {
                    NumberAnimation { target: hero; property: "x"; from: gallery.tx; to: gallery.ox; duration: 360; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: hero; property: "y"; from: gallery.ty; to: gallery.oy; duration: 360; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: hero; property: "width"; from: gallery.tw; to: gallery.ow; duration: 360; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: hero; property: "height"; from: gallery.th; to: gallery.oh; duration: 360; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: albumPageItem; property: "opacity"; from: 1; to: 0; duration: 320 }
                }
                ScriptAction { script: { hero.visible = false; pageCover.opacity = 1; win.albumPage = false } }
            }

            // ===== the album page: big cover on the left, songs on the right =====
            Item {
                id: albumPageItem
                anchors.fill: parent
                visible: win.albumPage
                opacity: 0
                z: 10
                clip: true
                readonly property real coverSize: Math.max(150, Math.min(height - 165, width * 0.36))
                readonly property string coverSrc: win.albumData ? win.coverOf(win.albumData) : ""
                // the four main colours of this album's cover (the neon palette until they are known)
                readonly property var palette: win.albumData ? backend.coverColors(win.albumData.cover, win.albumData.coverUrl)
                                                             : ["#B04CFF", "#FF2BD6", "#00F0FF", "#8A2BE2"]

                // background: the main colours of the cover, as big soft blobs that drift slowly, blurred together
                Item {
                    id: blobs
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 64
                        saturation: 0.25
                    }
                    Rectangle { anchors.fill: parent; color: "#0A0710" }
                    Blob {
                        color: albumPageItem.palette[0] || "#B04CFF"
                        areaW: albumPageItem.width; areaH: albumPageItem.height; running: albumPageItem.visible && win.visible
                        size: 0.80; fromX: 0.0; toX: 0.85; fromY: 0.05; toY: 0.70; duration: 13000
                    }
                    Blob {
                        color: albumPageItem.palette[1] || "#FF2BD6"
                        areaW: albumPageItem.width; areaH: albumPageItem.height; running: albumPageItem.visible && win.visible
                        size: 0.70; fromX: 1.0; toX: 0.10; fromY: 0.90; toY: 0.10; duration: 17000
                    }
                    Blob {
                        color: albumPageItem.palette[2] || "#00F0FF"
                        areaW: albumPageItem.width; areaH: albumPageItem.height; running: albumPageItem.visible && win.visible
                        size: 0.62; fromX: 0.30; toX: 0.95; fromY: 0.00; toY: 1.00; duration: 11000
                    }
                    Blob {
                        color: albumPageItem.palette[3] || "#8A2BE2"
                        areaW: albumPageItem.width; areaH: albumPageItem.height; running: albumPageItem.visible && win.visible
                        size: 0.55; fromX: 0.80; toX: 0.00; fromY: 0.40; toY: 0.95; duration: 15000
                    }
                }
                // darken a little so the text stays readable
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#8C0A0710" }
                        GradientStop { position: 1.0; color: "#B80A0710" }
                    }
                }
                MouseArea { anchors.fill: parent }          // keeps clicks away from the gallery below

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    anchors.bottomMargin: 88
                    spacing: 34

                    // ---- left: back button and the cover (neon glow, 3D tilt, pulses with the bass)
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: albumPageItem.coverSize
                        spacing: 16
                        NeonButton {
                            text: "< BACK"
                            accent: win.cyan
                            implicitWidth: 100
                            implicitHeight: 34
                            onClicked: gallery.closePage()
                        }
                        Item {
                            id: pageCover
                            Layout.preferredWidth: albumPageItem.coverSize
                            Layout.preferredHeight: albumPageItem.coverSize
                            readonly property real nx: coverHover.hovered ? Math.max(-1, Math.min(1, (coverHover.point.position.x / width - 0.5) * 2)) : 0
                            readonly property real ny: coverHover.hovered ? Math.max(-1, Math.min(1, (coverHover.point.position.y / height - 0.5) * 2)) : 0
                            property real tiltY: nx * 12
                            property real tiltX: -ny * 12
                            Behavior on tiltY { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                            Behavior on tiltX { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                            readonly property real bass: {
                                var b = viz.bars, s = 0
                                for (var i = 0; i < 6; i++) s += (b[i] || 0)
                                return s / 6
                            }

                            Item {
                                id: tiltBox
                                anchors.fill: parent
                                transform: [
                                    Rotation {
                                        origin.x: tiltBox.width / 2
                                        origin.y: tiltBox.height / 2
                                        axis { x: 1; y: 0; z: 0 }
                                        angle: pageCover.tiltX
                                    },
                                    Rotation {
                                        origin.x: tiltBox.width / 2
                                        origin.y: tiltBox.height / 2
                                        axis { x: 0; y: 1; z: 0 }
                                        angle: pageCover.tiltY
                                    }
                                ]
                                Image {
                                    id: pageImg
                                    anchors.fill: parent
                                    source: albumPageItem.coverSrc
                                    sourceSize: Qt.size(700, 700)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: pageImg
                                    source: pageImg
                                    shadowEnabled: true
                                    shadowColor: win.magenta
                                    shadowBlur: 1.0
                                    shadowOpacity: 0.45 + 0.5 * pageCover.bass
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.color: win.magenta
                                    border.width: 1
                                }
                                // light spot that follows the pointer
                                Item {
                                    anchors.fill: parent
                                    clip: true
                                    Rectangle {
                                        width: parent.width * 0.8
                                        height: width
                                        radius: width / 2
                                        x: (pageCover.nx * 0.5 + 0.5) * parent.width - width / 2
                                        y: (pageCover.ny * 0.5 + 0.5) * parent.height - height / 2
                                        color: "#FFFFFF"
                                        opacity: coverHover.hovered ? 0.10 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                    }
                                }
                            }
                            HoverHandler { id: coverHover }
                        }
                    }

                    // ---- right: album info, buttons, songs
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: win.albumData ? (win.isMine ? "\u2605 " : "") + win.albumData.name : ""
                            color: win.fg
                            font.bold: true
                            font.pixelSize: 30
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: win.albumData ? win.albumData.artist + (win.albumData.year > 0 ? "  \u00b7  " + win.albumData.year : "") : ""
                            color: win.magenta
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: win.albumData ? win.albumData.tracks.length + " songs  \u00b7  " + win.albumLength(win.albumData) : ""
                            color: win.dim
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 8
                            NeonButton { text: "PLAY"; accent: win.cyan; implicitWidth: 70; onClicked: backend.playAlbum(win.selectedIndex, 0) }
                            NeonButton { text: "EDIT"; accent: win.magenta; implicitWidth: 60; onClicked: albumDialog.openEdit(win.albumData) }
                            NeonButton { text: "+ FILES"; accent: win.magenta; implicitWidth: 80; onClicked: filesDialog.open() }
                                NeonButton { text: "EXPORT M3U"; accent: win.violet; implicitWidth: 104; onClicked: m3uSave.open() }
                            NeonButton { visible: win.isMine; text: "COVER"; accent: win.magenta; implicitWidth: 70; onClicked: coverDialog.open() }
                            NeonButton { visible: win.isMine; text: "DELETE"; accent: win.dim; implicitWidth: 72; onClicked: deleteDialog.open() }
                            NeonButton { visible: !win.isMine; text: "HIDE"; accent: win.dim; implicitWidth: 60; onClicked: { backend.hideAlbum(win.albumData.id); gallery.closeNow() } }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.edge }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ListView {
                                id: pageList
                                anchors.fill: parent
                                clip: true
                                property bool dragging: false
                                interactive: !dragging
                                model: win.albumData ? win.albumData.tracks : []
                                delegate: songRow
                                ScrollBar.vertical: ScrollBar {
                                    contentItem: Rectangle { implicitWidth: 6; color: win.violet; opacity: 0.7 }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: win.albumData !== null && win.albumData.tracks.length === 0
                                horizontalAlignment: Text.AlignHCenter
                                color: win.dim
                                font.family: "monospace"
                                text: "Empty album.\nUse + FILES, or the + button on any song."
                            }
                        }
                    }
                }

                // visualizer along the bottom of the page
                NeonBars {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 22
                    height: 58
                }
            }
        }

        // ---------- LIBRARY: all songs of the music folder, to pick songs for your albums ----------
        Item {
            id: libraryPage
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: win.libraryMode

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    color: win.panel
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 14
                        NeonField {
                            id: libSearch
                            Layout.fillWidth: true
                            placeholderText: "Search songs, artists, albums..."
                        }
                        Text {
                            text: libList.count + " SONGS"
                            color: win.dim
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.edge }
                Text {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    text: "Press + on a song to put it into one of your albums (for example Playlist). Double-click plays."
                    color: win.dim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        id: libList
                        anchors.fill: parent
                        clip: true
                        model: backend.librarySongs(libSearch.text, backend.rev)
                        ScrollBar.vertical: ScrollBar {
                            contentItem: Rectangle { implicitWidth: 6; color: win.violet; opacity: 0.7 }
                        }
                        delegate: Item {
                            id: lrow
                            width: ListView.view.width
                            height: 40
                            readonly property bool cur: backend.currentIndex === modelData.idx
                            readonly property bool onBtn: lEd.hovered || lAdd.hovered
                            readonly property color hot: lAdd.hovered ? win.cyan : win.violet
                            HoverHandler { id: lhover }
                            Rectangle {
                                anchors.fill: parent
                                color: lrow.onBtn ? Qt.rgba(lrow.hot.r, lrow.hot.g, lrow.hot.b, 0.22)
                                       : (cur ? win.card : (lhover.hovered ? win.panel : "transparent"))
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Rectangle {
                                width: 3
                                height: parent.height
                                color: lrow.onBtn ? lrow.hot : (cur ? win.cyan : "transparent")
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onDoubleClicked: {
                                    var ids = []
                                    var m = libList.model
                                    for (var i = 0; i < m.length; i++) ids.push(m[i].idx)
                                    backend.playSongs(ids, index)
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                spacing: 12
                                Text { Layout.preferredWidth: 40; text: index + 1; color: cur ? win.cyan : win.dim; font.family: "monospace" }
                                Text { Layout.fillWidth: true; text: modelData.title; color: cur ? win.cyan : win.fg; elide: Text.ElideRight }
                                Text { Layout.preferredWidth: 170; text: modelData.artist; color: win.magenta; font.pixelSize: 12; elide: Text.ElideRight }
                                Text { Layout.preferredWidth: 170; text: modelData.album; color: win.dim; font.pixelSize: 12; elide: Text.ElideRight }
                                Text { text: win.fmt(modelData.length * 1000); color: win.dim; font.family: "monospace" }
                                NeonButton {
                                    id: lEd
                                    text: "ED"
                                    accent: win.violet
                                    implicitWidth: 32
                                    implicitHeight: 26
                                    onClicked: trackDialog.openFor(modelData)
                                }
                                NeonButton {
                                    id: lAdd
                                    text: "+"
                                    accent: win.cyan
                                    implicitWidth: 28
                                    implicitHeight: 26
                                    onClicked: { addPopup.trackIdx = modelData.idx; addPopup.open() }
                                }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: libList.count === 0
                        horizontalAlignment: Text.AlignHCenter
                        color: win.dim
                        font.family: "monospace"
                        text: backend.scanning ? "SCANNING..." : (libSearch.text !== "" ? "Nothing found." : "No songs in\n" + backend.folder)
                    }
                }
            }
        }

        // ---------- now playing bar ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 108
            color: win.panel
            Rectangle { width: parent.width; height: 1; color: win.magenta }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 16

                Image {
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 80
                    source: backend.currentCover !== "" ? backend.currentCover
                            : "image://cover/" + backend.currentIndex + "?v=" + backend.version
                    sourceSize: Qt.size(160, 160)
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                }

                ColumnLayout {
                    Layout.preferredWidth: 220
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: backend.currentTitle !== "" ? backend.currentTitle : "Nothing playing"
                        color: win.fg
                        font.bold: true
                        font.pixelSize: 15
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: backend.currentArtist
                        color: win.magenta
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: backend.currentAlbum
                        color: win.dim
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        NeonButton {
                            text: "SHUF"
                            accent: win.violet
                            active: backend.shuffle
                            implicitWidth: 58
                            onClicked: backend.toggleShuffle()
                        }
                        NeonButton { text: "|<"; accent: win.cyan; onClicked: backend.prev() }
                        NeonButton {
                            text: backend.playing ? "||" : ">"
                            accent: win.magenta
                            implicitWidth: 64
                            implicitHeight: 40
                            fontSize: 16
                            onClicked: backend.togglePlay()
                        }
                        NeonButton { text: ">|"; accent: win.cyan; onClicked: backend.next() }
                        NeonButton {
                            text: backend.repeatMode === 2 ? "REP 1" : "REP"
                            accent: win.violet
                            active: backend.repeatMode !== 0
                            implicitWidth: 58
                            onClicked: backend.cycleRepeat()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: win.fmt(seekSlider.pressed ? seekSlider.value : backend.positionMs); color: win.dim; font.family: "monospace"; font.pixelSize: 12 }
                        NeonSlider {
                            id: seekSlider
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(1, backend.durationMs)
                            // while you drag, the audio is NOT touched; one single seek happens on release
                            // (seeking on every mouse move made the sound stutter)
                            property bool hold: false
                            Binding on value {
                                value: backend.positionMs
                                when: !seekSlider.pressed && !seekSlider.hold
                            }
                            onPressedChanged: {
                                if (!pressed) {
                                    backend.seek(value)
                                    hold = true                 // keep the handle still until the player has jumped
                                    holdTimer.restart()
                                }
                            }
                            onMoved: if (!pressed) backend.seek(value)      // arrow keys
                            Timer { id: holdTimer; interval: 350; onTriggered: seekSlider.hold = false }
                        }
                        Text { text: win.fmt(backend.durationMs); color: win.dim; font.family: "monospace"; font.pixelSize: 12 }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 130
                    spacing: 2
                    Text { text: "VOL " + Math.round(backend.volume * 100); color: win.dim; font.family: "monospace"; font.pixelSize: 12 }
                    NeonSlider {
                        Layout.fillWidth: true
                        accent: win.violet
                        from: 0
                        to: 1
                        value: backend.volume
                        onMoved: backend.volume = value
                    }
                }
            }
        }
    }
}
