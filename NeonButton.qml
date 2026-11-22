import QtQuick
import QtQuick.Shapes

// Button with cut corners (top-left and bottom-right), neon outline.
// Smooth: fill and outline fade on hover/active, the button presses in, and the label cross-fades
// when it changes (for example > <-> || on the play button).
Item {
    id: root
    property string text: ""
    property color accent: "#B04CFF"
    property bool active: false
    property int fontSize: 12
    signal clicked()
    readonly property bool hovered: mouse.containsMouse

    implicitWidth: 44
    implicitHeight: 36
    readonly property real cut: Math.min(width, height) * 0.28

    // the label that is actually drawn; it follows `text` through a short cross-fade
    property string shownText: text
    onTextChanged: if (text !== shownText) swap.restart()

    scale: mouse.pressed ? 0.93 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4
        ShapePath {
            strokeColor: root.accent
            strokeWidth: (mouse.containsMouse || root.active) ? 2 : 1.5
            Behavior on strokeWidth { NumberAnimation { duration: 140 } }
            fillColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
                               mouse.pressed ? 0.55 : ((mouse.containsMouse || root.active) ? 0.30 : 0.10))
            Behavior on fillColor { ColorAnimation { duration: 150 } }
            startX: root.cut
            startY: 0.75
            PathLine { x: root.width - 0.75; y: 0.75 }
            PathLine { x: root.width - 0.75; y: root.height - root.cut }
            PathLine { x: root.width - root.cut; y: root.height - 0.75 }
            PathLine { x: 0.75; y: root.height - 0.75 }
            PathLine { x: 0.75; y: root.cut }
            PathLine { x: root.cut; y: 0.75 }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.shownText
        color: (mouse.pressed || root.active) ? "#FFFFFF" : root.accent
        Behavior on color { ColorAnimation { duration: 150 } }
        font.family: "monospace"
        font.bold: true
        font.pixelSize: root.fontSize
    }

    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: label; property: "opacity"; to: 0; duration: 70 }
            NumberAnimation { target: label; property: "scale"; to: 0.6; duration: 70 }
        }
        ScriptAction { script: root.shownText = root.text }
        ParallelAnimation {
            NumberAnimation { target: label; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
            NumberAnimation { target: label; property: "scale"; to: 1; duration: 160; easing.type: Easing.OutBack }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
