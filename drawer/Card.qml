import QtQuick
import QtQuick.Layouts

// A neon-framed section of the drawer.
Rectangle {
    id: card
    property string title: ""
    property color accent: "#B04CFF"
    default property alias content: body.data
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 36
    color: "#9914091F"
    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.55)
    border.width: 1

    Text {
        x: 10
        y: 6
        text: card.title
        color: card.accent
        font.family: "monospace"
        font.pixelSize: 10
        font.letterSpacing: 2
    }
    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        anchors.topMargin: 24
        spacing: 6
    }
}
