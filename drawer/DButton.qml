import QtQuick

// Small neon button.
Rectangle {
    id: btn
    property string text: ""
    property color accent: "#00F0FF"
    property bool active: false
    signal clicked()
    implicitWidth: label.implicitWidth + 22
    implicitHeight: 26
    color: ma.pressed ? Qt.rgba(accent.r, accent.g, accent.b, 0.55)
         : (ma.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.30)
         : (active ? Qt.rgba(accent.r, accent.g, accent.b, 0.20) : "#661C1030"))
    border.color: accent
    border.width: 1
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        color: btn.active || ma.containsMouse ? "#FFFFFF" : btn.accent
        font.family: "monospace"
        font.pixelSize: 11
        font.bold: true
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
