import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // ---- palette (CyberNeon) ----
    readonly property color cPanel: "#14091F"
    readonly property color cEdge: "#3B1F6B"
    readonly property color cViolet: "#B04CFF"
    readonly property color cMagenta: "#FF2BD6"
    readonly property color cCyan: "#00F0FF"
    readonly property color cFg: "#EDE6FF"
    readonly property color cDim: "#8C7FAD"

    // ---- state coming from the player ----
    property var stFile: ({ running: false })       // slow fallback: state.json, once per second
    property var stHttp: ({ running: false })       // fast feed from the player, ~12 times per second
    property bool httpOk: false
    property bool busy: false
    property bool cardVisible: false
    property double pendingUntil: 0          // after a play/pause click, trust our own guess for a moment
    property bool pendingPlay: false
    readonly property var st: httpOk ? stHttp : stFile
    readonly property bool online: st.running === true
    property int tick: 0
    readonly property string feedUrl: "http://127.0.0.1:47615/state"

    readonly property string stateCmd: "cat \"$HOME/.cache/cyberneon-player/state.json\" 2>/dev/null"
    readonly property string ctl: "\"$HOME/.local/bin/cyberneon-ctl\""
    readonly property string launcher: "setsid \"$HOME/.local/bin/cyberneon-player\" >/dev/null 2>&1 &"

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function fmt(ms) {
        var s = Math.max(0, Math.floor(ms / 1000))
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function send(cmd) {
        if (cmd === "playpause" && root.httpOk) {          // optimistic: the button reacts immediately
            var s = Object.assign({}, root.stHttp)
            s.playing = !s.playing
            root.pendingPlay = s.playing
            root.pendingUntil = Date.now() + 600
            root.stHttp = s
        }
        exec.run(ctl + " " + cmd)
        quick.restart()
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            if (sourceName.indexOf("state.json") !== -1) {
                try {
                    var j = JSON.parse((data["stdout"] || "").trim())
                    if (Date.now() / 1000 - j.ts > 5) j.running = false
                    root.stFile = j
                } catch (e) {
                    root.stFile = ({ running: false })
                }
            }
        }
        function run(cmd) {
            connectSource(cmd + " #" + (root.tick++))
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.run(root.stateCmd)
    }
    function pollFeed() {
        if (busy) return
        busy = true
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            busy = false
            if (xhr.status === 200) {
                try {
                    var j = JSON.parse(xhr.responseText)
                    if (Date.now() < root.pendingUntil) j.playing = root.pendingPlay    // avoid a flicker back
                    root.stHttp = j
                    root.httpOk = true
                    return
                } catch (e) { }
            }
            root.httpOk = false
        }
        xhr.open("GET", feedUrl)
        xhr.timeout = 700
        xhr.send()
    }
    Timer {
        interval: root.cardVisible && root.httpOk && root.st.playing ? 50 : 400
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollFeed()
    }
    Timer {
        id: quick
        interval: 300
        onTriggered: exec.run(root.stateCmd)
    }

    // ---- small cut-corner button ----
    component NeonBtn: Item {
        id: b
        property string label: ""
        property color accent: root.cViolet
        property bool active: false
        property int fontSize: 11
        signal clicked()
        implicitWidth: 40
        implicitHeight: 28
        readonly property real cut: Math.min(width, height) * 0.28

        // label cross-fades when it changes (> <-> || on the play button)
        property string shown: label
        onLabelChanged: if (label !== shown) swap.restart()

        scale: ma.pressed ? 0.93 : 1.0
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                strokeColor: b.accent
                strokeWidth: (ma.containsMouse || b.active) ? 2 : 1.5
                Behavior on strokeWidth { NumberAnimation { duration: 140 } }
                fillColor: Qt.rgba(b.accent.r, b.accent.g, b.accent.b,
                                   ma.pressed ? 0.55 : ((ma.containsMouse || b.active) ? 0.30 : 0.10))
                Behavior on fillColor { ColorAnimation { duration: 150 } }
                startX: b.cut
                startY: 0.75
                PathLine { x: b.width - 0.75; y: 0.75 }
                PathLine { x: b.width - 0.75; y: b.height - b.cut }
                PathLine { x: b.width - b.cut; y: b.height - 0.75 }
                PathLine { x: 0.75; y: b.height - 0.75 }
                PathLine { x: 0.75; y: b.cut }
                PathLine { x: b.cut; y: 0.75 }
            }
        }
        Text {
            id: txt
            anchors.centerIn: parent
            text: b.shown
            color: (ma.pressed || b.active) ? "#FFFFFF" : b.accent
            Behavior on color { ColorAnimation { duration: 150 } }
            font.family: "monospace"
            font.bold: true
            font.pixelSize: b.fontSize
        }
        SequentialAnimation {
            id: swap
            ParallelAnimation {
                NumberAnimation { target: txt; property: "opacity"; to: 0; duration: 70 }
                NumberAnimation { target: txt; property: "scale"; to: 0.6; duration: 70 }
            }
            ScriptAction { script: b.shown = b.label }
            ParallelAnimation {
                NumberAnimation { target: txt; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: txt; property: "scale"; to: 1; duration: 160; easing.type: Easing.OutBack }
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }

    // ---- small icon shown when the widget sits in a panel ----
    compactRepresentation: Item {
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
        Text {
            anchors.centerIn: parent
            text: root.online && root.st.playing ? "||" : ">"
            color: root.cMagenta
            font.family: "monospace"
            font.bold: true
            font.pixelSize: Math.max(10, Math.min(parent.width, parent.height) * 0.55)
        }
    }

    // ---- the card ----
    fullRepresentation: Item {
        id: card
        Layout.minimumWidth: 340
        Layout.minimumHeight: 196
        Layout.preferredWidth: 380
        Layout.preferredHeight: 210

        readonly property real cut: 16
        onVisibleChanged: root.cardVisible = visible
        Component.onCompleted: root.cardVisible = visible

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                strokeColor: root.cViolet
                strokeWidth: 1.5
                fillColor: Qt.rgba(0.078, 0.035, 0.122, 0.80)
                startX: card.cut
                startY: 0.75
                PathLine { x: card.width - 0.75; y: 0.75 }
                PathLine { x: card.width - 0.75; y: card.height - card.cut }
                PathLine { x: card.width - card.cut; y: card.height - 0.75 }
                PathLine { x: 0.75; y: card.height - 0.75 }
                PathLine { x: 0.75; y: card.cut }
                PathLine { x: card.cut; y: 0.75 }
            }
        }

        // offline state
        ColumnLayout {
            anchors.centerIn: parent
            visible: !root.online
            spacing: 10
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "PLAYER OFFLINE"
                color: root.cDim
                font.family: "monospace"
                font.bold: true
                font.pixelSize: 14
            }
            NeonBtn {
                Layout.alignment: Qt.AlignHCenter
                label: "OPEN"
                accent: root.cCyan
                implicitWidth: 90
                onClicked: exec.run(root.launcher)
            }
        }

        // online state
        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            anchors.bottomMargin: 58
            spacing: 14
            visible: root.online

            Rectangle {
                Layout.preferredWidth: 100
                Layout.preferredHeight: 100
                Layout.alignment: Qt.AlignVCenter
                color: "#1C1030"
                border.color: root.cEdge
                border.width: 1
                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: root.st.cover ? "file://" + root.st.cover : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.send("show")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: root.st.title ? root.st.title : "Nothing playing"
                    color: root.cFg
                    font.bold: true
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: root.st.artist ? root.st.artist : ""
                    color: root.cMagenta
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                // progress bar (click to seek)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        color: root.cEdge
                        Rectangle {
                            height: parent.height
                            width: root.st.duration > 0 ? parent.width * Math.min(1, root.st.position / root.st.duration) : 0
                            Behavior on width { NumberAnimation { duration: 120 } }
                            color: root.cCyan
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function (mouse) {
                            if (root.st.duration > 0)
                                root.send("seek " + Math.round(mouse.x / width * root.st.duration))
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: root.fmt(root.st.position || 0); color: root.cDim; font.family: "monospace"; font.pixelSize: 11 }
                    Item { Layout.fillWidth: true }
                    Text { text: root.fmt(root.st.duration || 0); color: root.cDim; font.family: "monospace"; font.pixelSize: 11 }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    NeonBtn { label: "SH"; accent: root.cViolet; active: root.st.shuffle === true; onClicked: root.send("shuffle") }
                    NeonBtn { label: "|<"; accent: root.cCyan; onClicked: root.send("prev") }
                    NeonBtn {
                        label: root.st.playing ? "||" : ">"
                        accent: root.cMagenta
                        implicitWidth: 52
                        fontSize: 14
                        onClicked: root.send("playpause")
                    }
                    NeonBtn { label: ">|"; accent: root.cCyan; onClicked: root.send("next") }
                    NeonBtn {
                        label: root.st.repeat === 2 ? "R1" : "RP"
                        accent: root.cViolet
                        active: root.st.repeat > 0
                        onClicked: root.send("repeat")
                    }
                }
            }
        }

        // neon visualizer
        Row {
            id: vbars
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.bottomMargin: 18
            height: 32
            spacing: 2
            visible: root.online
            Repeater {
                model: 40
                Item {
                    width: (vbars.width - 39 * vbars.spacing) / 40
                    height: vbars.height
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(2, ((root.st.bars && root.st.bars[index]) || 0) * parent.height)
                        Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: root.cMagenta }
                            GradientStop { position: 1.0; color: root.cCyan }
                        }
                    }
                }
            }
        }
    }
}
