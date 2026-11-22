import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import org.kde.layershell 1.0 as LayerShell

// Two layer-shell windows (like Plasma's own panels, so "Show Desktop" does not hide them):
//  - a 2 px invisible strip on the left screen edge that notices the pointer
//  - the drawer itself, shown while the pointer is on it, with a slide-in / slide-out animation
QtObject {
    id: app
    property int bottomReserve: 64            // space left for the bottom Plasma panel (px)

    property var hotZone: Window {
        id: hot
        width: 2
        height: Screen.height - app.bottomReserve
        visible: true
        flags: Qt.FramelessWindowHint
        color: "transparent"
        title: "CyberNeon Drawer edge"
        LayerShell.Window.scope: "cyberneon-drawer-edge"
        LayerShell.Window.anchors: LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorTop
        LayerShell.Window.layer: LayerShell.Window.LayerTop
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

        HoverHandler {
            onHoveredChanged: {
                if (!hovered) win.armed = true
                else if (win.armed && !win.shown) win.openDrawer()
            }
        }
    }

    property var drawerWindow: Window {
    id: win
    width: 380
    height: Screen.height - app.bottomReserve
    visible: false
    flags: Qt.FramelessWindowHint
    color: "transparent"
    title: "CyberNeon Drawer"
    LayerShell.Window.scope: "cyberneon-drawer"
    LayerShell.Window.anchors: LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorTop
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand

    readonly property color panel: "#14091F"
    readonly property color edge: "#3B1F6B"
    readonly property color violet: "#B04CFF"
    readonly property color magenta: "#FF2BD6"
    readonly property color cyan: "#00F0FF"
    readonly property color fg: "#EDE6FF"
    readonly property color dim: "#8C7FAD"

    property bool shown: false
    property bool armed: true                 // the pointer has been outside the window since the last close
    property bool pinned: false
    property real slide: -400                 // x of the panel: 0 = in, negative = hidden to the left
    property date now: new Date()
    property var st: ({})
    property bool online: false

    Behavior on slide {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
            onRunningChanged: if (!running && !win.shown) win.visible = false    // fully hidden: unmap the window
        }
    }

    function openDrawer() {
        leave.stop()
        armed = false
        shown = true
        visible = true
        slide = 0
        backend.refresh()
        poll()
        grace.restart()
    }
    function closeDrawer() {
        if (!shown) return
        shown = false
        saver.stop()
        backend.saveNotes(notes.text)
        slide = -(win.width + 30)
    }
    onActiveChanged: if (!active && shown && !pinned && !hover.hovered) closeDrawer()

    Shortcut { sequence: "Escape"; onActivated: win.closeDrawer() }
    Timer { id: grace; interval: 1800; onTriggered: if (!hover.hovered && !win.pinned) win.closeDrawer() }
    Timer { id: leave; interval: 600; onTriggered: win.closeDrawer() }
    Timer {
        interval: 1000
        repeat: true
        running: win.shown
        onTriggered: { backend.refresh(); win.now = new Date() }
    }

    // ---- player state from the player's local feed (same one the Plasma widget uses) ----
    property bool busy: false
    function poll() {
        if (busy) return
        busy = true
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            busy = false
            try {
                if (x.status === 200) { win.st = JSON.parse(x.responseText); win.online = win.st.running === true }
                else win.online = false
            } catch (e) { win.online = false }
        }
        x.open("GET", "http://127.0.0.1:47615/state")
        x.send()
    }
    Timer {
        interval: win.online && win.st.playing ? 100 : 600
        repeat: true
        running: win.shown
        onTriggered: win.poll()
    }
    function fmt(ms) {
        var s = Math.max(0, Math.floor(ms / 1000))
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    // ---- the panel ----
    Item {
        id: panelItem
        x: win.slide + 10
        y: 10
        width: win.width - 20
        height: win.height - 20

        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered) leave.stop()
                else if (!win.pinned && win.shown) leave.restart()
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#E60A0710"
            border.color: win.violet
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "CYBERNEON // DRAWER"
                    color: win.magenta
                    font.family: "monospace"
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 2
                    Layout.fillWidth: true
                }
                DButton { text: win.pinned ? "PINNED" : "PIN"; accent: win.cyan; active: win.pinned; onClicked: win.pinned = !win.pinned }
                DButton { text: "<<"; accent: win.magenta; onClicked: { win.pinned = false; win.closeDrawer() } }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: col.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

                ColumnLayout {
                    id: col
                    width: flick.width - 6
                    spacing: 8

                    // ---------- clock ----------
                    Card {
                        title: "// TIME"
                        accent: win.cyan
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: Qt.formatDateTime(win.now, "HH:mm")
                                color: win.fg
                                font.family: "monospace"
                                font.pixelSize: 44
                                font.bold: true
                            }
                            Text {
                                text: Qt.formatDateTime(win.now, "ss")
                                color: win.magenta
                                font.family: "monospace"
                                font.pixelSize: 18
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 8
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                spacing: 0
                                Text { text: Qt.formatDateTime(win.now, "dddd").toUpperCase(); color: win.cyan; font.family: "monospace"; font.pixelSize: 12; Layout.alignment: Qt.AlignRight }
                                Text { text: Qt.formatDateTime(win.now, "d MMMM yyyy"); color: win.dim; font.family: "monospace"; font.pixelSize: 11; Layout.alignment: Qt.AlignRight }
                            }
                        }
                    }

                    // ---------- player ----------
                    Card {
                        title: "// NOW PLAYING"
                        accent: win.magenta

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                Layout.preferredWidth: 76
                                Layout.preferredHeight: 76
                                color: "#1C1030"
                                border.color: win.edge
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    source: win.online && win.st.cover ? "file://" + win.st.cover : ""
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: !win.online ? "Player is not running" : (win.st.title ? win.st.title : "Nothing playing")
                                    color: win.fg
                                    font.pixelSize: 15
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: win.online && win.st.artist ? win.st.artist : ""
                                    color: win.magenta
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: win.online ? win.fmt(win.st.position || 0) + " / " + win.fmt(win.st.duration || 0) : ""
                                    color: win.dim
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 8
                            color: win.edge
                            Rectangle {
                                width: win.online && win.st.duration > 0 ? parent.width * Math.min(1, win.st.position / win.st.duration) : 0
                                height: parent.height
                                color: win.cyan
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function (m) {
                                    if (win.online && win.st.duration > 0)
                                        backend.send("seek " + Math.round(Math.max(0, Math.min(1, m.x / width)) * win.st.duration))
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            DButton { text: win.online ? "START" : "START"; visible: !win.online; accent: win.cyan; onClicked: backend.launch("cyberneon-player") }
                            DButton { visible: win.online; text: "SH"; accent: win.violet; active: win.st.shuffle === true; onClicked: backend.send("shuffle") }
                            DButton { visible: win.online; text: "|<"; accent: win.cyan; onClicked: backend.send("prev") }
                            DButton { visible: win.online; text: win.st.playing ? "||" : ">"; accent: win.magenta; implicitWidth: 56; onClicked: backend.send("playpause") }
                            DButton { visible: win.online; text: ">|"; accent: win.cyan; onClicked: backend.send("next") }
                            DButton { visible: win.online; text: win.st.repeat === 2 ? "R1" : "RP"; accent: win.violet; active: win.st.repeat > 0; onClicked: backend.send("repeat") }
                            Item { Layout.fillWidth: true }
                        }
                        Item {
                            visible: win.online
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            Row {
                                anchors.fill: parent
                                spacing: 2
                                Repeater {
                                    model: 40
                                    Item {
                                        width: (parent.width - 39 * 2) / 40
                                        height: parent.height
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: Math.max(2, ((win.st.bars && win.st.bars[index]) || 0) * parent.height)
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: win.magenta }
                                                GradientStop { position: 1.0; color: win.cyan }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---------- system ----------
                    Card {
                        title: "// SYSTEM"
                        accent: win.violet
                        Meter { label: "CPU"; accent: win.cyan; value: backend.stats.cpu || 0; valueText: Math.round((backend.stats.cpu || 0) * 100) + " %" }
                        Meter { label: "RAM"; accent: win.violet; value: backend.stats.mem || 0; valueText: backend.stats.memText || "" }
                        Meter { label: "DISK"; accent: win.magenta; value: backend.stats.disk || 0; valueText: backend.stats.diskText || "" }
                        Meter {
                            visible: (backend.stats.temp || -1) > 0
                            label: "TEMP"
                            accent: win.cyan
                            value: Math.max(0, ((backend.stats.temp || 0) - 30) / 70)
                            valueText: Math.round(backend.stats.temp || 0) + " C"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "NET"; color: win.dim; font.family: "monospace"; font.pixelSize: 11; Layout.preferredWidth: 38 }
                            Text { text: "v " + (backend.stats.down || ""); color: win.cyan; font.family: "monospace"; font.pixelSize: 11; Layout.fillWidth: true }
                            Text { text: "^ " + (backend.stats.up || ""); color: win.magenta; font.family: "monospace"; font.pixelSize: 11 }
                        }
                    }

                    // ---------- volume ----------
                    Card {
                        title: "// VOLUME"
                        accent: win.cyan
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            DButton { text: backend.muted ? "MUTED" : "MUTE"; accent: win.magenta; active: backend.muted; onClicked: backend.toggleMute() }
                            DSlider {
                                id: volSlider
                                Layout.fillWidth: true
                                accent: win.violet
                                from: 0
                                to: 1
                                value: backend.volume
                                onMoved: volTimer.restart()
                            }
                            Text { text: Math.round(backend.volume * 100) + ""; color: win.fg; font.family: "monospace"; font.pixelSize: 12; Layout.preferredWidth: 28; horizontalAlignment: Text.AlignRight }
                        }
                        Timer { id: volTimer; interval: 60; onTriggered: backend.setVolume(volSlider.value) }
                    }

                    // ---------- launchers ----------
                    Card {
                        title: "// LAUNCH"
                        accent: win.magenta
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: backend.launchers
                                DButton {
                                    text: modelData.name
                                    accent: index % 2 === 0 ? win.cyan : win.violet
                                    onClicked: { backend.launch(modelData.cmd); if (!win.pinned) win.closeDrawer() }
                                }
                            }
                        }
                    }

                    // ---------- notes ----------
                    Card {
                        title: "// NOTES"
                        accent: win.cyan
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
                            color: "#66000000"
                            border.color: win.edge
                            Flickable {
                                id: notesFlick
                                anchors.fill: parent
                                anchors.margins: 6
                                clip: true
                                contentHeight: notes.implicitHeight
                                TextArea.flickable: TextArea {
                                    id: notes
                                    color: win.fg
                                    selectionColor: win.violet
                                    wrapMode: TextArea.Wrap
                                    selectByMouse: true
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    background: null
                                    placeholderText: "Quick notes. Saved automatically."
                                    placeholderTextColor: win.dim
                                    Component.onCompleted: text = backend.loadNotes()
                                    onTextChanged: saver.restart()
                                }
                            }
                        }
                        Timer { id: saver; interval: 700; onTriggered: backend.saveNotes(notes.text) }
                    }
                }
            }
        }
    }
}
}
