import QtQuick
import QtQuick.Controls.Basic

Slider {
    id: control
    property color accent: "#00F0FF"
    implicitHeight: 22

    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth
        height: 4
        color: "#3B1F6B"
        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            color: control.accent
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: 12
        height: 12
        rotation: 45
        color: control.pressed ? "#FFFFFF" : control.accent
    }
}
