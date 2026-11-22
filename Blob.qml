import QtQuick

// A big soft circle of colour that drifts slowly around the area; several of them,
// blurred together, make the moving colour background of the album page.
Rectangle {
    id: blob
    property real areaW: 800
    property real areaH: 500
    property real size: 0.7            // diameter as a share of the larger side of the area
    property real fromX: 0.0
    property real toX: 1.0
    property real fromY: 0.0
    property real toY: 1.0
    property int duration: 12000
    property bool running: true

    readonly property real sz: Math.max(areaW, areaH) * size
    property real px: fromX
    property real py: fromY

    width: sz
    height: sz
    radius: sz / 2
    x: px * (areaW - sz)
    y: py * (areaH - sz)
    opacity: 0.9

    Behavior on color { ColorAnimation { duration: 900 } }

    SequentialAnimation on px {
        running: blob.running
        loops: Animation.Infinite
        NumberAnimation { to: blob.toX; duration: blob.duration; easing.type: Easing.InOutSine }
        NumberAnimation { to: blob.fromX; duration: blob.duration; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on py {
        running: blob.running
        loops: Animation.Infinite
        NumberAnimation { to: blob.toY; duration: Math.round(blob.duration * 1.3); easing.type: Easing.InOutSine }
        NumberAnimation { to: blob.fromY; duration: Math.round(blob.duration * 1.3); easing.type: Easing.InOutSine }
    }
    SequentialAnimation on scale {
        running: blob.running
        loops: Animation.Infinite
        NumberAnimation { to: 1.18; duration: Math.round(blob.duration * 0.8); easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.88; duration: Math.round(blob.duration * 0.8); easing.type: Easing.InOutSine }
    }
}
