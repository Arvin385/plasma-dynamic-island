import QtQuick 2.15

// Static grain + highlight lines over the pill background. Extracted from
// main.qml (Phase 2). Anchors.fill its parent (the background); pass `radius`.
Rectangle {
    id: overlay

    color: "transparent"
    property real subtleOpacity: 0.035

    // Static grain only — animated particles were fighting the visualizer
    Repeater {
        model: 6
        Rectangle {
            width: 1 + (index % 2)
            height: 1
            x: (index * 53) % Math.max(1, Math.floor(parent.width))
            y: (index * 29) % Math.max(1, Math.floor(parent.height))
            radius: 0.5
            color: Qt.rgba(0, 0, 0, 0.25)
            opacity: 0.08 + (index % 3) * 0.03
        }
    }

    Rectangle {
        width: parent.width * 0.6
        height: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.15
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.3) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
        opacity: overlay.subtleOpacity * 0.7
    }

    Rectangle {
        width: parent.width * 0.8
        height: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.15
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.3) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
        }
        opacity: overlay.subtleOpacity * 0.7
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: overlay.radius - 1
        color: "transparent"
        border.width: 0
        border.color: Qt.rgba(1, 1, 1, overlay.subtleOpacity * 0.3)
    }
}
