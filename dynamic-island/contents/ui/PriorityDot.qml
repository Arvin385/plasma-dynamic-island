import QtQuick 2.15

Item {
    id: root
    width: 14
    height: 14
    property bool prioritized: false
    property color accent: "#3DDC97"
    signal clicked()

    Rectangle {
        anchors.centerIn: parent
        width: prioritized ? 12 : 10
        height: width
        radius: width / 2
        color: prioritized ? root.accent : Qt.rgba(1, 1, 1, 0.22)
        border.width: prioritized ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.35)
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 180 } }

        Rectangle {
            visible: root.prioritized
            anchors.centerIn: parent
            width: parent.width + 8
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
            z: -1
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
