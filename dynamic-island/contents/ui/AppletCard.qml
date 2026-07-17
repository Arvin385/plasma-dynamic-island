import QtQuick 2.15

Item {
    id: root
    property var islandRoot
    property string modeId: "system"
    property string title: ""
    property bool alwaysShow: false
    property bool active: false
    property color cardColor: "#2A5A8C"
    property Component contentComponent

    readonly property bool shown: true
    readonly property bool prioritized: islandRoot && islandRoot.priorityMode === modeId
    readonly property bool dimmed: modeId !== "system" && !active

    visible: true
    height: card.implicitHeight
    width: parent ? parent.width : 400
    opacity: 1
    clip: true

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: row.implicitHeight + 16
        height: implicitHeight
        radius: 14
        color: root.prioritized ? Qt.lighter(root.cardColor, 1.15) : root.cardColor
        opacity: root.dimmed ? 0.72 : 1
        border.width: 0

        Row {
            id: row
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 8
            width: parent.width - 16

            PriorityDot {
                anchors.verticalCenter: parent.verticalCenter
                prioritized: root.prioritized
                accent: islandRoot ? islandRoot.accentGreen : "#3DDC97"
                onClicked: if (islandRoot) islandRoot.setPriority(root.modeId)
            }

            Column {
                width: parent.width - 22
                spacing: 3

                Text {
                    text: root.title
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.9
                    font.capitalization: Font.AllUppercase
                    font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
                }

                Loader {
                    width: parent.width
                    sourceComponent: root.contentComponent
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            onEntered: if (islandRoot) islandRoot.cancelCollapse()
            onClicked: {
                if (!islandRoot) return
                if (modeId === "system") islandRoot.activateSystemMonitor()
                else if (modeId === "media") islandRoot.activateMediaPlayer()
                else if (modeId === "llm") islandRoot.activateLlmRunner()
                else if (modeId === "install") islandRoot.activateInstallTerminal()
            }
        }
    }
}
