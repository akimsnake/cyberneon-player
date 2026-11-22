import QtQuick
import QtQuick.Layouts

// Label, a thin neon bar and a value text.
RowLayout {
    property string label: ""
    property real value: 0
    property string valueText: ""
    property color accent: "#00F0FF"
    Layout.fillWidth: true
    spacing: 8

    Text { text: label; color: "#8C7FAD"; font.family: "monospace"; font.pixelSize: 11; Layout.preferredWidth: 38 }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        color: "#3B1F6B"
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, value))
            height: parent.height
            color: value > 0.85 ? "#FF2BD6" : accent
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
    }
    Text { text: valueText; color: "#EDE6FF"; font.family: "monospace"; font.pixelSize: 11; Layout.preferredWidth: 92; horizontalAlignment: Text.AlignRight }
}
