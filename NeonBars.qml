import QtQuick

// Neon equalizer bars driven by the player's visualizer (context property `viz`).
Item {
    id: root
    property color topColor: "#FF2BD6"
    property color bottomColor: "#00F0FF"
    property int count: 40
    property real gap: 3

    Row {
        id: row
        anchors.fill: parent
        spacing: root.gap
        Repeater {
            model: root.count
            Item {
                width: (row.width - (root.count - 1) * root.gap) / root.count
                height: row.height
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(2, (viz.bars[index] || 0) * parent.height)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.topColor }
                        GradientStop { position: 1.0; color: root.bottomColor }
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
}
