import QtQuick 2.15

// Install/uninstall progress — inset track + sliding thumb (stays inside the pill
// caps). Extracted from main.qml (Phase 2). Parent supplies the anchored geometry;
// pass `active` and `removing`.
Item {
    id: track

    property bool active: false
    property bool removing: false

    height: 3
    visible: opacity > 0.01
    opacity: active ? 1 : 0
    clip: true

    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    readonly property color accent: removing ? "#FF6B6B" : "#5BB0FF"
    // 0 → 1 travel fraction (x is derived so resize never overflows)
    property real sweep: 0

    // Subtle track
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.14)
    }

    // Sliding thumb — travels within the track, never grows past edges
    Rectangle {
        id: progressThumb
        width: Math.max(28, parent.width * 0.32)
        height: parent.height
        radius: height / 2
        y: 0
        x: track.sweep * Math.max(0, parent.width - width)
        color: track.accent
        opacity: 0.95

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.35) }
                GradientStop { position: 0.45; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.15) }
            }
        }
    }

    SequentialAnimation {
        running: track.opacity > 0.5
        loops: Animation.Infinite
        NumberAnimation {
            target: track
            property: "sweep"
            from: 0
            to: 1
            duration: 1100
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: track
            property: "sweep"
            from: 1
            to: 0
            duration: 1100
            easing.type: Easing.InOutSine
        }
    }
}
