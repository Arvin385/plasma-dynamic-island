import QtQuick 2.15

// Six-bar sine visualizer. Extracted from main.qml (Phase 2).
// One timer drives all bars (no per-bar animation graphs). Pass `active`.
Row {
    id: visualizer

    property bool active: false
    visible: active
    spacing: 3
    height: 22
    property real phase: 0

    Timer {
        interval: 40
        running: visualizer.visible
        repeat: true
        onTriggered: visualizer.phase += 0.18
    }

    Repeater {
        model: 6
        Rectangle {
            width: 3
            radius: 1.5
            anchors.verticalCenter: parent.verticalCenter
            readonly property real barPhase: index * 0.85
            height: 4 + 14 * (0.5 + 0.5 * Math.sin(visualizer.phase + barPhase))
            color: Qt.hsla(((index * 38 + 265) % 360) / 360, 0.72, 0.68, 0.95)
        }
    }
}
