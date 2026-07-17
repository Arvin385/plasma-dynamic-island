import QtQuick 2.15

Item {
    id: root
    property var islandRoot

    implicitWidth: 410
    implicitHeight: stack.implicitHeight + 26
    width: implicitWidth
    height: implicitHeight

    // Floating minimize — tiny, top-right
    Rectangle {
        width: 20
        height: 20
        radius: 10
        z: 20
        anchors.right: parent.right
        anchors.top: parent.top
        color: Qt.rgba(0.16, 0.16, 0.18, 0.92)
        Text {
            anchors.centerIn: parent
            text: "▾"
            color: "#fff"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: if (islandRoot) islandRoot.cancelCollapse()
            onClicked: {
                if (islandRoot) {
                    islandRoot.cancelCollapse()
                    islandRoot.expanded = false
                }
            }
        }
    }

    Column {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 22
        spacing: 6

        AppletCard {
            width: parent.width
            islandRoot: root.islandRoot
            modeId: "system"
            title: "System"
            alwaysShow: true
            cardColor: "#1E4D6B"
            contentComponent: systemBody
        }
        AppletCard {
            width: parent.width
            islandRoot: root.islandRoot
            modeId: "media"
            title: "Media"
            alwaysShow: true
            active: islandRoot && islandRoot.mediaModeActive
            cardColor: "#5B2A7A"
            contentComponent: mediaBody
        }
        AppletCard {
            width: parent.width
            islandRoot: root.islandRoot
            modeId: "llm"
            title: "Local LLM"
            alwaysShow: true
            active: islandRoot && islandRoot.llmModeActive
            cardColor: "#0D5C56"
            contentComponent: llmBody
        }
        AppletCard {
            width: parent.width
            islandRoot: root.islandRoot
            modeId: "install"
            title: "Packages"
            alwaysShow: true
            active: islandRoot && islandRoot.installModeActive
            cardColor: {
                if (!islandRoot || !islandRoot.installModeActive) return "#1E4A7A"
                var a = String((islandRoot.installData && islandRoot.installData.action) || "")
                if (a.indexOf("remov") >= 0 || a.indexOf("uninstall") >= 0) return "#7A2A2A"
                if (a.indexOf("installed") >= 0 || a.indexOf("removed") >= 0) return "#2A6B45"
                return "#1E4A7A"
            }
            contentComponent: installBody
        }
    }

    Component {
        id: systemBody
        Text {
            width: parent ? parent.width : 360
            text: {
                var s = islandRoot ? islandRoot.sysData : {}
                var line = "CPU " + Math.round(Number(s.cpu || 0)) + "%"
                         + " · RAM " + Math.round(Number(s.ram || 0)) + "%"
                var gpus = (s && s.gpus) ? s.gpus : []
                for (var i = 0; i < (gpus ? gpus.length : 0); ++i)
                    line += " · " + (gpus[i].name || ("GPU" + i))
                         + " " + Math.round(Number(gpus[i].util || 0)) + "%"
                return line
            }
            color: "#FFFFFF"
            font.pixelSize: 12
            font.weight: Font.Medium
            font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    Component {
        id: mediaBody
        Column {
            spacing: 2
            width: parent ? parent.width : 360
            property bool live: islandRoot && islandRoot.mediaModeActive
            property var m: islandRoot ? islandRoot.mediaData : ({})
            Text {
                width: parent.width
                text: live
                    ? (function () {
                        var t = m.title || "—"
                        var a = m.artist || ""
                        return a ? (t + "  —  " + a) : t
                    })()
                    : "No media currently playing"
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: live ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: live ? 13 : 12
                font.weight: live ? Font.DemiBold : Font.Medium
                font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
            }
            Text {
                width: parent.width
                visible: live
                text: {
                    var parts = []
                    if (m.source) parts.push(m.source)
                    if (m.speaker) parts.push(m.speaker)
                    return parts.join(" · ")
                }
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 11
                elide: Text.ElideRight
                font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
            }
        }
    }

    Component {
        id: llmBody
        Column {
            spacing: 2
            width: parent ? parent.width : 360
            property bool live: islandRoot && islandRoot.llmModeActive
            property var l: islandRoot ? islandRoot.llmData : ({})
            Text {
                width: parent.width
                text: live
                    ? ((l.model || "Model") + "  ·  " + (l.runner || "?") + "  ·  ctx " + (l.context || "—"))
                    : "No local models detected"
                color: live ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 12
                font.weight: live ? Font.DemiBold : Font.Medium
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
            }
            Text {
                width: parent.width
                visible: live
                text: {
                    var sizeMb = Number(l.ram_mb || l.size_mb || 0)
                    var sizeLabel = sizeMb >= 1024
                        ? (sizeMb / 1024).toFixed(2) + " GB"
                        : Math.round(sizeMb) + " MB"
                    var phase = String(l.phase || "idle")
                    var tps = Number(l.tokens_per_second || 0)
                    var phaseTxt
                    if (phase === "idle")
                        phaseTxt = "idle"
                    else if (tps > 0)
                        phaseTxt = tps.toFixed(1) + " tok/s"
                    else
                        phaseTxt = "processing"
                    return "CPU " + Math.round(Number(l.cpu || 0)) + "%"
                         + " · RAM " + sizeLabel
                         + " · GPU " + Math.round(Number(l.gpu || 0)) + "%"
                         + " · " + phaseTxt
                }
                color: Qt.rgba(1, 1, 1, 0.8)
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
            }
        }
    }

    Component {
        id: installBody
        Column {
            spacing: 2
            width: parent ? parent.width : 360
            property bool live: islandRoot && islandRoot.installModeActive
            property var i: islandRoot ? islandRoot.installData : ({})
            Text {
                width: parent.width
                text: live
                    ? ((i.action || "") + " " + (i.package || "")).trim()
                    : "No current installations occurring"
                color: live ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 12
                font.weight: live ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
            }
            Text {
                width: parent.width
                text: live ? (i.command || "") : ""
                visible: live && text.length > 0
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 10
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: islandRoot ? islandRoot.uiFont : "sans-serif"
            }
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (!islandRoot) return
            if (hovered) islandRoot.cancelCollapse()
            else islandRoot.scheduleCollapse()
        }
    }
}
