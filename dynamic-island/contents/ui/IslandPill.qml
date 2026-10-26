import QtQuick 2.15
import QtQuick.Layouts 1.15

// Compact-representation shell for the pill: background + rim + texture +
// visualizer + progress + label + animations. Extracted from main.qml (Phase 2).
// Reads shared state from `islandRoot`; visual colors come from ModeColors so the
// pill, cards and text share one mapping.
Item {
    id: mainContainer

    property var islandRoot

    Layout.fillWidth: false
    Layout.fillHeight: false
    Layout.preferredWidth: islandRoot ? islandRoot.animatedWidth : 200
    Layout.preferredHeight: islandRoot ? islandRoot.fixedHeight : 48
    Layout.minimumWidth: islandRoot ? islandRoot.minWidth : 120
    Layout.maximumWidth: islandRoot ? islandRoot.maxWidth : 650
    Layout.minimumHeight: islandRoot ? islandRoot.fixedHeight : 48
    Layout.maximumHeight: islandRoot ? islandRoot.fixedHeight : 48
    width: islandRoot ? islandRoot.animatedWidth : 200
    height: islandRoot ? islandRoot.fixedHeight : 48

    Rectangle {
        id: background
        anchors.fill: parent
        radius: height / 2 + 3
        border.width: 0
        clip: true

        property color dominantColor: islandRoot
            ? ModeColors.pillColor(
                islandRoot.priorityMode,
                String((islandRoot.installData && islandRoot.installData.action) || ""),
                islandRoot.isInstalling,
                islandRoot.isUninstalling,
                islandRoot.isInstalled,
                islandRoot.isUninstalled,
                islandRoot.isMediaOnly
            )
            : Qt.rgba(0.08, 0.08, 0.08, 1.0)

        border.color: Qt.darker(Qt.lighter(dominantColor, 1.2), 1.2)
        color: dominantColor

        opacity: hovered ? 1.0 : 0.9
        scale: hovered ? 1.02 : 1.0

        Behavior on scale {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        property bool hovered: false

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onEntered: {
                background.hovered = true
                if (islandRoot) islandRoot.openExpanded()
            }
            onExited: {
                background.hovered = false
                if (islandRoot) islandRoot.scheduleCollapse()
            }

            onClicked: {
                if (!islandRoot) return
                if (islandRoot.priorityMode === "install")
                    islandRoot.activateInstallTerminal()
                else if (islandRoot.priorityMode === "media")
                    islandRoot.activateMediaPlayer()
                else if (islandRoot.priorityMode === "system" || islandRoot.priorityMode === "idle")
                    islandRoot.activateSystemMonitor()
            }
        }
    }

    FlowingRim {
        anchors.centerIn: parent
        z: 999
        dominantColor: background.dominantColor
        hovered: background.hovered
        rimThickness: 5.5
        pillWidth: islandRoot ? islandRoot.width : 0
        pillHeight: islandRoot ? islandRoot.height : 0
        pillActive: islandRoot ? islandRoot.visible : false
    }

    TextureOverlay {
        anchors.fill: background
        radius: background.radius
    }

    // Media visualizer — shown only when the pill is actually showing media
    MediaVisualizer {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 16
        z: 3
        active: islandRoot ? islandRoot.isMediaOnly : false
    }

    // Install/uninstall progress — inset track + sliding thumb (stays inside pill caps)
    InstallProgress {
        anchors.left: background.left
        anchors.right: background.right
        anchors.bottom: background.bottom
        // Inset past the stadium end-caps so the bar never bleeds out the sides
        anchors.leftMargin: Math.max(background.height * 0.5, 18)
        anchors.rightMargin: Math.max(background.height * 0.5, 18)
        anchors.bottomMargin: 6
        z: 4
        active: islandRoot ? (islandRoot.isInstalling || islandRoot.isUninstalling) : false
        removing: islandRoot
            ? (islandRoot.isUninstalling
               || String((islandRoot.installData && islandRoot.installData.action) || "").indexOf("remov") >= 0
               || String((islandRoot.installData && islandRoot.installData.action) || "").indexOf("uninstall") >= 0)
            : false
    }

    // Modern typography with masculine hierarchy
    Item {
        id: textWrapper
        anchors.fill: parent
        opacity: 1.0
        z: 999

        // Smooth fade behavior
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        // Trigger fade manually when content changes
        Timer {
            id: fadeInTimer
            interval: 0
            repeat: false
            onTriggered: textWrapper.opacity = 1.0
        }

        Text {
            id: textDisplay
            text: islandRoot ? islandRoot.visibleDisplayText : ""
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: (islandRoot && islandRoot.isMediaOnly)
                ? (islandRoot.padding + islandRoot.visualizerGutter)
                : (islandRoot ? islandRoot.padding : 20)
            anchors.rightMargin: islandRoot ? islandRoot.padding : 20

            font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
            font.pixelSize: 14
            font.weight: Font.Medium
            font.letterSpacing: 0.3
            color: islandRoot
                ? ModeColors.textColor(
                    islandRoot.isInstalling,
                    islandRoot.isUninstalling,
                    islandRoot.isInstalled,
                    islandRoot.isUninstalled,
                    islandRoot.isMediaOnly,
                    islandRoot.isDefaultState
                )
                : "#FFFFFF"

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            antialiasing: true
            clip: true

            onTextChanged: {
                textWrapper.opacity = 0.0
                fadeInTimer.start()
            }
        }
    }

    // Subtle breathing animation for active states
    SequentialAnimation {
        running: islandRoot ? (islandRoot.isInstalling || islandRoot.isUninstalling) : false
        loops: Animation.Infinite
        NumberAnimation {
            target: background
            property: "opacity"
            from: 0.95
            to: 1.0
            duration: 2500
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: background
            property: "opacity"
            from: 1.0
            to: 0.95
            duration: 2500
            easing.type: Easing.InOutSine
        }
    }

    // Smooth width transition (match root animatedWidth easing)
    Behavior on width {
        NumberAnimation { duration: 520; easing.type: Easing.InOutCubic }
    }

    Behavior on scale {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
}
