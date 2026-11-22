import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: control
    color: "#EDE6FF"
    placeholderTextColor: "#8C7FAD"
    selectionColor: "#8A2BE2"
    selectedTextColor: "#FFFFFF"
    font.pixelSize: 14
    leftPadding: 10
    rightPadding: 10
    implicitHeight: 36
    selectByMouse: true
    background: Rectangle {
        color: "#0A0710"
        border.width: 1
        border.color: control.activeFocus ? "#00F0FF" : "#3B1F6B"
    }
}
