import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1 as Platform
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasma5support 2.0 as P5Support
import QtQuick.Effects

PlasmoidItem {
    id: root

    // Widget properties
    property string statusText: ""
    property string mediaText: ""
    property string activePlayer: ""
    property bool showPulse: false
    property int padding: 20
    property int minWidth: 340
    property int maxWidth: 650
    property int fixedHeight: 48
    property real systemLoad: 0.0
    property int temperature: 0
    property int networkSpeed: 0
    property string currentTime: ""
    property bool showSystemInfo: false
    property real hueShift: 0.0

    property real animatedWidth: minWidth
    property real lastTargetWidth: minWidth
    property real cachedTextWidth: 0

    property real measuredTextWidth: 0

/*
    onMediaTextChanged: {
        delayedUpdateTimer.restart()
    }
    onShowSystemInfoChanged: updateAnimatedWidth()*/

    property int currentState: {
        if (dbusIsPlaying) return 5

            if (cleanStatusText.includes("installing") && !cleanStatusText.includes("installed")) return 1
                if (cleanStatusText.includes("uninstalling") && !cleanStatusText.includes("uninstalled")) return 2
                    if (cleanStatusText.includes("installed")) return 3
                        if (cleanStatusText.includes("uninstalled")) return 4

                            return 0
    }


    // Normalized lowercase version of statusText
    property string cleanStatusText: statusText.toString().toLowerCase().trim()

    // Enhanced content detection with modern symbols (case-insensitive)
    property bool isInstalling: cleanStatusText.includes("installing") || cleanStatusText.includes("downloading") || statusText.includes("▼") || statusText.includes("●")
    property bool isUninstalling: cleanStatusText.includes("uninstalling") || cleanStatusText.includes("removing") || statusText.includes("×")
    property bool isInstalled: cleanStatusText.includes("installed") || cleanStatusText.includes("downloaded") || cleanStatusText.includes("✓") || cleanStatusText.includes("completed")
    property bool isUninstalled: cleanStatusText.includes("uninstalled") || cleanStatusText.includes("removed")

    property bool isSystemActive: isInstalling || isUninstalling
    property bool isSystemCompleted: isInstalled || isUninstalled

    property bool isMediaOnly: (mediaText !== "" || cleanStatusText.includes("♫") || cleanStatusText.includes("♪") || cleanStatusText.includes("now playing") || cleanStatusText.includes("spotify")) && !isSystemActive && !isSystemCompleted

    property bool hasMedia: mediaText !== ""
    property bool hasStatus: statusText !== ""
    property bool hasContent: hasMedia || hasStatus
    property bool isDefaultState: !hasContent


    // File paths
    property string homeDirectory: Platform.StandardPaths.writableLocation(Platform.StandardPaths.HomeLocation).toString().replace("file://", "")
    property string statusFile: homeDirectory + "/.cache/dynamic-island-status.txt"
    property string mediaFile: homeDirectory + "/.cache/dynamic-island-media.txt"

    // Show widget when there's content OR in default state
    visible: hasContent || isDefaultState

    // Responsive sizing with smooth transitions
    Layout.fillWidth: false
    Layout.fillHeight: false
    Layout.preferredWidth: animatedWidth

    // Layout.preferredWidth: {
    //     if (isDefaultState) return minWidth
    //         var contentWidth = Math.max(textDisplay.implicitWidth + padding * 2, minWidth)
    //         if (isMediaOnly) contentWidth += 80
    //             if (showSystemInfo) contentWidth += 120
    //                 return Math.max(Math.min(contentWidth, maxWidth), minWidth)
    // }
    Layout.preferredHeight: fixedHeight
    Layout.minimumWidth: minWidth
    Layout.maximumWidth: maxWidth
    Layout.minimumHeight: fixedHeight
    Layout.maximumHeight: fixedHeight

    width: animatedWidth
    height: Layout.preferredHeight

    preferredRepresentation: fullRepresentation

    // System info timer
    Timer {
        id: systemInfoTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            updateSystemInfo()
        }
    }

    // Time update timer
    Timer {
        id: timeTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            currentTime = new Date().toLocaleTimeString(Qt.locale(), "hh:mm")
        }
    }

    // Enhanced file polling
    Timer {
        id: filePoller
        interval: 10
        running: true
        repeat: true
        onTriggered: {
            readStatusFile()
            readMediaFile()
        }
    }

    // Initialization
    Timer {
        id: initTimer
        interval: 800
        running: true
        repeat: false
        onTriggered: {
            console.log("=== Enhanced Dynamic Island Initialized ===")
            console.log("Status:", statusText)
            console.log("Media:", mediaText)
            console.log("Size:", width + "x" + height)
            currentTime = new Date().toLocaleTimeString(Qt.locale(), "hh:mm")
        }
    }


    Timer {
        id: textWidthCacheTimer
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (textDisplay.implicitWidth > 0) {
                cachedTextWidth = textDisplay.implicitWidth
            }
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: 100  // delay to allow text layout
        repeat: false
        onTriggered: {
            updateAnimatedWidth()
        }
    }


    Timer {
        id: measureTextTimer
        interval: 30
        repeat: true
        running: false
        property int ticks: 0

        onTriggered: {
            if (textDisplay.implicitWidth > measuredTextWidth)
                measuredTextWidth = textDisplay.implicitWidth

                ticks++
                if (ticks > 10) {  // ~300ms total
                    stop()
                    finalizeWidthUpdate()
                }
        }
    }

    Timer {
        id: startupWidthTimer
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            startWidthMeasurement()
        }
    }

    Timer {
        id: mediaTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: mediaReader.readFile()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const xhr = new XMLHttpRequest()
            xhr.open("GET", "file://" + Qt.resolvedUrl("~/.cache/dynamic-island-media.txt"))
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 0) {
                    const lines = xhr.responseText.split("\n")
                    if (lines.length >= 2) {
                        mediaText = lines[0].trim()
                        activePlayer = lines[1].trim()
                        console.log("🎵 Media mode. Player:", activePlayer)
                    }
                }
            }
            xhr.send()
        }
    }


    QtObject {
        id: mediaReader

        function readFile() {
            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 0) {
                    var raw = xhr.responseText.trim()
                    if (raw !== mediaText) {
                        mediaText = raw
                        activePlayer = "dbus"  // Dummy value so you can check for state 5
                    }
                }
            }
            xhr.open("GET", "file://" + plasmoid.configuration.homePath + "/.cache/dynamic-island-media.txt")
            xhr.send()
        }
    }

    function startWidthMeasurement() {
        measuredTextWidth = 0
        measureTextTimer.ticks = 0
        measureTextTimer.restart()
    }

    onStatusTextChanged: {
        startWidthMeasurement()
        if (isInstalled || isUninstalled)
            autoHideTimer.restart()
            else
                autoHideTimer.stop()
    }


    onMediaTextChanged: startWidthMeasurement()
    onShowSystemInfoChanged: startWidthMeasurement()



    NumberAnimation {
        id: widthAnim
        target: root
        property: "animatedWidth"
        duration: 400
        easing.type: Easing.OutCubic
    }

    Behavior on animatedWidth {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }


    function calculateTargetWidth() {
        var textWidth = textDisplay.implicitWidth
        var extra = 0
        if (isMediaOnly) extra += 80
            if (showSystemInfo) extra += 120
                var total = Math.max(textWidth + padding * 2 + extra, minWidth)
                return Math.min(total, maxWidth)
    }
    function updateAnimatedWidth() {
        // Measure the real width needed to fit the full text
        var idealTextWidth = textDisplay.implicitWidth
        var extra = 0
        if (isMediaOnly) extra += 80
            if (showSystemInfo) extra += 120

                // Calculate the total width needed for full content
                var neededWidth = idealTextWidth + padding * 2 + extra

                // Clamp to maxWidth if necessary
                var clampedWidth = Math.min(neededWidth, maxWidth)

                // Only animate if width is changing
                if (clampedWidth !== lastTargetWidth) {
                    lastTargetWidth = clampedWidth
                    widthAnim.to = clampedWidth
                    widthAnim.start()
                    console.log("🌿 Animating to:", clampedWidth)
                }
    }




    function finalizeWidthUpdate() {
        var sideMargin = padding * 4 + 50
        var extra = 0
        if (isMediaOnly) extra += 80
            if (showSystemInfo) extra += 120

                var total = measuredTextWidth + sideMargin + extra
                var clamped = Math.min(total, maxWidth)

                if (clamped !== lastTargetWidth) {
                    lastTargetWidth = clamped
                    widthAnim.to = clamped
                    widthAnim.start()
                }
    }



    function handleWidgetClick() {
        console.log("**Just checking... Player:", dbusPlayer)

        if (currentState === 5 && dbusPlayer) {
            console.log("🎵 Media mode. Player:", dbusPlayer)
            launchApp(dbusPlayer)
        }
    }



    function runApp(appName) {
        // Prefer xdg-open if available
        Qt.openUrlExternally("applications://" + appName)
        // or fallback:
        // KRun.runCommand(appName)
    }

    function launchMediaSourceApp(playerName) {
        if (!playerName)
            return

            var name = playerName.toLowerCase()

            if (name.includes("spotify"))
                Qt.openUrlExternally("spotify:")
                else if (name.includes("vlc"))
                    Qt.openUrlExternally("vlc:")
                    else if (name.includes("clementine"))
                        Qt.openUrlExternally("clementine:")
                        else if (name.includes("firefox"))
                            Qt.openUrlExternally("firefox:")
                            else if (name.includes("chrome"))
                                Qt.openUrlExternally("google-chrome:")
                                else
                                    console.log("❌ No known handler for player:", playerName)
    }




    // Enhanced MPRIS2 support
    P5Support.DataSource {
        id: mprisSource
        engine: "mpris2"
        connectedSources: []
        interval: 10

        onNewData: {
            console.log("🎤 MPRIS new data from:", sourceName)
            console.log("🧾 Full data:", JSON.stringify(data))
            // if (data && typeof data === 'object') {
            //     updateMediaInfo(sourceName, data)
            // }
            updateMediaInfo(sourceName, data)
        }

        onSourceAdded: {
            connectSource(source)
        }

        onSourceRemoved: {
            disconnectSource(source)
            if (activePlayer === source) {
                activePlayer = ""
            }
        }




        function connectAllSources() {
            var availableSources = sources
            for (var i = 0; i < availableSources.length; i++) {
                var source = availableSources[i]
                if (connectedSources.indexOf(source) === -1) {
                    connectSource(source)
                }
            }
        }

        Component.onCompleted: connectAllSources()
        onSourcesChanged: connectAllSources()
    }


    /// Apple-Quality Dynamic Island Visual Shell
    /// Enhanced for luxury, precision, depth, and animation

    NumberAnimation {
        target: root
        property: "hueShift"
        from: 0.0
        to: 1.0
        duration: 10000
        loops: Animation.Infinite
        easing.type: Easing.Linear
        running: true
    }

    fullRepresentation: Item {
        id: mainContainer
        width: root.Layout.preferredWidth
        height: root.Layout.preferredHeight

        // Rectangle {
        //     id: shadowBackground
        //     anchors.fill: parent
        //     anchors.margins: -8
        //     radius: (height / 2) + 3
        //     color: Qt.rgba(0, 0, 0, 0.22)
        //     z: -3
        // }
        //
        // Rectangle {
        //     id: shadowSecondary
        //     anchors.fill: parent
        //     anchors.margins: -4
        //     radius: (height / 2) + 3
        //     color: Qt.rgba(0, 0, 0, 0.12)
        //     z: -2
        // }
        Rectangle {
            id: background
            anchors.fill: parent
            radius: height / 2 + 3
            border.width: 0
            anchors.centerIn: background

            property color dominantColor: {
                if (isInstalling) return Qt.rgba(0.12, 0.35, 0.65, 1.0)
                    if (isUninstalling) return Qt.rgba(0.75, 0.25, 0.15, 1.0)
                        if (isInstalled) return Qt.rgba(0.15, 0.55, 0.25, 1.0)
                            if (isUninstalled) return Qt.rgba(0.6, 0.45, 0.15, 1.0)
                                if (isMediaOnly) return Qt.rgba(0.4, 0.2, 0.5, 1.0)
                                    return Qt.rgba(0.08, 0.08, 0.08, 1.0)
            }

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

            // PropertyAnimation {
            //     id: clickPulse
            //     target: background
            //     property: "scale"
            //     to: 1.05
            //     duration: 80
            //     easing.type: Easing.OutQuad
            //     onFinished: background.scale = 1.02
            // }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onEntered: background.hovered = true
                onExited: background.hovered = false



                onClicked: {
                    // 📡 Call DBus adaptor for current player
                    var player = MediaBridge.call("GetPlayer").toString().toLowerCase()
                    console.log("🎵 Media mode. Player:", player)

                    // ⚙️ Map MPRIS service → app desktop IDs
                    var appMap = {
                        "spotify": "spotify",
                        "vlc": "vlc",
                        "firefox": "firefox",
                        "chrome": "google-chrome",
                        "brave": "brave-browser",
                        "chromium": "chromium",
                        "youtube": "firefox", // fallback
                    }

                    if (player && appMap[player]) {
                        var desktopEntry = appMap[player]
                        console.log("🚀 Launching app:", desktopEntry)
                        Qt.openUrlExternally("application://" + desktopEntry + ".desktop")
                    } else {
                        console.log("❌ No known handler for player:", player)
                    }
                }



            }
        }


        Canvas {
            id: flowingRim
            width: root.width + rimThickness * 2
            height: root.height + rimThickness * 2
            anchors.centerIn: parent
            z: 999

            property real rimThickness: 5.5
            property bool fhovered: false
            property real gradientShift: 0

            transformOrigin: Item.Center
            scale: fhovered ? 1.02 : 1.0
            Behavior on scale {
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }

            Connections {
                target: background
                onHoveredChanged: flowingRim.fhovered = background.hovered
            }

            function qmlColorToRgba(c, a = 1.0) {
                return `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a})`
            }

            function blendColors(c1, c2, ratio) {
                return Qt.rgba(
                    c1.r * (1 - ratio) + c2.r * ratio,
                               c1.g * (1 - ratio) + c2.g * ratio,
                               c1.b * (1 - ratio) + c2.b * ratio,
                               1
                )
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()

                const w = root.width
                const h = root.height
                const r = h / 2 + 3
                const strokeInset = rimThickness

                ctx.translate(strokeInset, strokeInset)

                function qmlColorToRgba(c, a = 1.0) {
                    return `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a})`
                }

                const dom = background.dominantColor
                const bright = qmlColorToRgba(Qt.lighter(dom, 2.2), 1.0)
                const dim = qmlColorToRgba(Qt.darker(dom, 1.4), 1.0)

                const mintAccent = Qt.rgba(0, 1, 0.8, 1)  // bright mint
                const purpAccent = Qt.rgba(0.6, 0.2, 0.9, 1)
                const goldAccent = Qt.rgba(1, 0.85, 0.3, 1)

                const domMint = blendColors(dom, mintAccent, 0.2)

                const domPurp = blendColors(dom, purpAccent, 0.2)
                const domGold = blendColors(dom, goldAccent, 0.2)

                const mintPurp = blendColors(domMint, domPurp, 0.4)
                const purpGold = blendColors(domPurp, domGold, 0.4)

                const loopWidth = w * 8  // Wider for smoother looping
                const offset = gradientShift % loopWidth
                const gradient = ctx.createLinearGradient(-loopWidth + offset, 0, offset, 0)

                gradient.addColorStop(0.00, bright)
                gradient.addColorStop(0.15, domMint)  // mint
                gradient.addColorStop(0.30, bright)
                gradient.addColorStop(0.40, mintPurp) // mint-purple
                gradient.addColorStop(0.50, domPurp)  // purple
                gradient.addColorStop(0.60, purpGold) // purple-gold
                gradient.addColorStop(0.70, bright)
                gradient.addColorStop(0.85, domGold)  // gold
                gradient.addColorStop(0.37, bright)
                gradient.addColorStop(1.00, bright)



                ctx.save()
                ctx.beginPath()
                ctx.moveTo(r, 0)
                ctx.lineTo(w - r, 0)
                ctx.quadraticCurveTo(w, 0, w, r)
                ctx.lineTo(w, h - r)
                ctx.quadraticCurveTo(w, h, w - r, h)
                ctx.lineTo(r, h)
                ctx.quadraticCurveTo(0, h, 0, h - r)
                ctx.lineTo(0, r)
                ctx.quadraticCurveTo(0, 0, r, 0)
                ctx.closePath()
                ctx.clip()

                ctx.strokeStyle = gradient
                ctx.lineWidth = rimThickness
                ctx.stroke()
                ctx.restore()
            }



            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: {
                    flowingRim.gradientShift += 8
                    flowingRim.requestPaint()
                }
            }
        }







        Rectangle {
            id: textureOverlay
            anchors.fill: background
            radius: background.radius
            color: "transparent"
            property real subtleOpacity: 0.035
            property bool enableMicroAnimations: true

            Repeater {
                model: 10
                Rectangle {
                    width: 1 + (index % 2)
                    height: 1 + ((index + 1) % 2)
                    x: Math.random() * parent.width
                    y: Math.random() * parent.height
                    radius: 0.5
                    color: Qt.rgba(0, 0, 0, 0.25)
                    opacity: 0.1 + (index % 3) * 0.05

                    SequentialAnimation on opacity {
                        running: textureOverlay.enableMicroAnimations
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.15; duration: 5000 + index * 300 }
                        NumberAnimation { to: 0.05; duration: 5000 + index * 300 }
                    }
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
                opacity: subtleOpacity * 0.7
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
                opacity: subtleOpacity * 0.7
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 0
                border.color: Qt.rgba(1, 1, 1, subtleOpacity * 0.3)
            }
        }
    }
        // System info display
        Row {
            id: systemInfoRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            //anchors.horizontalCenterOffset: +10

            anchors.verticalCenterOffset: +10
            anchors.rightMargin: 20
            spacing: 12
            visible: showSystemInfo && !isMediaOnly
            opacity: 0.8

            // CPU indicator
            Row {
                spacing: 4
                Text {
                    text: "▲"
                    color: systemLoad > 0.7 ? "#FF6B6B" : systemLoad > 0.4 ? "#FFD93D" : "#6BCF7F"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
                Text {
                    text: Math.round(systemLoad * 100) + "%"
                    color: "#FFFFFF"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.family: "JetBrains Mono, Monaco, monospace"
                }
            }

            // Temperature indicator
            Row {
                spacing: 4
                visible: temperature > 0
                Text {
                    text: "◆"
                    color: temperature > 70 ? "#FF6B6B" : temperature > 50 ? "#FFD93D" : "#6BCF7F"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
                Text {
                    text: temperature + "°"
                    color: "#FFFFFF"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.family: "JetBrains Mono, Monaco, monospace"
                }
            }

            // Time display
            // Text {
            //     text: currentTime
            //     color: "#FFFFFF"
            //     font.pixelSize: 12
            //     font.weight: Font.Medium
            //     font.family: "JetBrains Mono, Monaco, monospace"
            //     opacity: 0.9
            // }
        }

        // Enhanced media visualizer with modern geometric design
        Row {
            id: mediaVisualizer
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 20
            spacing: 3
            visible: isMediaOnly
            z: 3

            Repeater {
                model: 6
                Rectangle {
                    width: 2.5
                    height: 6 + Math.random() * 10
                    color: {
                        var hue = (index * 60 + 240) % 360
                        return Qt.hsla(hue / 360, 0.8, 0.7, 0.9)
                    }

                    // Hexagonal bars for modern look
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        color: parent.color

                        transform: Rotation {
                            angle: index * 6
                            origin.x: width / 2
                            origin.y: height / 2
                        }
                    }

                    SequentialAnimation on height {
                        running: isMediaOnly
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 3 + Math.random() * 15
                            duration: 800 + Math.random() * 400
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: 6 + Math.random() * 10
                            duration: 800 + Math.random() * 400
                            easing.type: Easing.InOutSine
                        }
                    }

                    SequentialAnimation on opacity {
                        running: isMediaOnly
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.6 + Math.random() * 0.3
                            duration: 1000 + Math.random() * 500
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: 0.9
                            duration: 1000 + Math.random() * 500
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }
        }

        // Modern geometric progress indicator
        Rectangle {
            id: progressIndicator
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 3
            height: 2
            width: 0
            color: {
                if (isInstalling) return "#4A90E2"
                    if (isUninstalling) return "#E24A4A"
                        return "#4A90E2"
            }
            opacity: 0
            z: 2

            // Gradient overlay for depth
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: parent.color }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            states: [
                State {
                    name: "active"
                    when: isInstalling || isUninstalling
                    PropertyChanges { target: progressIndicator; opacity: 1.0 }
                },
                State {
                    name: "inactive"
                    when: !isInstalling && !isUninstalling
                    PropertyChanges { target: progressIndicator; opacity: 0; width: 0 }
                }
            ]

            transitions: [
                Transition {
                    to: "active"
                    NumberAnimation { properties: "opacity"; duration: 300; easing.type: Easing.OutCubic }
                },
                Transition {
                    to: "inactive"
                    NumberAnimation { properties: "opacity,width"; duration: 500; easing.type: Easing.InCubic }
                }
            ]

            SequentialAnimation {
                running: isInstalling || isUninstalling
                loops: Animation.Infinite
                NumberAnimation {
                    target: progressIndicator
                    property: "width"
                    from: parent.width * 0.1
                    to: parent.width * 0.9
                    duration: 2000
                    easing.type: Easing.InOutCubic
                }
                PauseAnimation { duration: 200 }
                NumberAnimation {
                    target: progressIndicator
                    property: "width"
                    from: parent.width * 0.9
                    to: parent.width * 0.1
                    duration: 2000
                    easing.type: Easing.InOutCubic
                }
            }
        }

        // Modern typography with masculine hierarchy
        // Text {
        //     id: textDisplay
        //     text: getDisplayText()
        //     z: 999
        //     wrapMode: Text.WordWrap
        //     maximumLineCount: 1
        //     elide: Text.ElideRight
        //     anchors.centerIn: parent
        //     anchors.leftMargin: isMediaOnly ? 80 : 0
        //     anchors.rightMargin: showSystemInfo ? 120 : 0
        //     width: Math.min(parent.width - root.padding * 2 - (isMediaOnly ? 80 : 0) - (showSystemInfo ? 120 : 0), maxWidth - root.padding * 2)
        //
        //     font.family: "JetBrains Mono, Fira Code, SF Mono, Monaco, monospace"
        //     font.pixelSize: {
        //         if (isDefaultState) return 14
        //             if (isMediaOnly) return 13
        //                 return 13
        //     }
        //     font.weight: {
        //         if (isSystemActive) return Font.Bold
        //             if (isSystemCompleted) return Font.DemiBold
        //                 if (isMediaOnly) return Font.Medium
        //                     return Font.Medium
        //     }
        //     font.letterSpacing: 0.5
        //
        //     color: {
        //         if (isInstalling) return "#E8F4FD"
        //             if (isUninstalling) return "#FDE8E8"
        //                 if (isInstalled) return "#E8F5E8"
        //                     if (isUninstalled) return "#FDF4E8"
        //                         if (isMediaOnly) return "#F4E8FD"
        //                             if (isDefaultState) return "#E0E0E0"
        //                                 return "#FFFFFF"
        //     }
        //
        //     horizontalAlignment: Text.AlignHCenter
        //     verticalAlignment: Text.AlignVCenter
        //     renderType: Text.NativeRendering
        //     antialiasing: true
        //
        //     Behavior on opacity {
        //         NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        //     }
        //     Behavior on color {
        //         ColorAnimation { duration: 400; easing.type: Easing.OutCubic }
        //     }
        // }
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
                text: getDisplayText()
                //elide: Text.ElideRight
                elide: Text.ElideNone         // ← allows implicitWidth to reflect true length
                wrapMode: Text.NoWrap         // ← keeps it single line
                maximumLineCount: 1
                anchors.centerIn: parent
                anchors.leftMargin: isMediaOnly ? 80 : 0
                anchors.rightMargin: showSystemInfo ? 120 : 0
                width: Math.min(parent.width - root.padding * 2 - (isMediaOnly ? 80 : 0) - (showSystemInfo ? 120 : 0), maxWidth - root.padding * 2)

                font.family: "JetBrains Mono, Fira Code, SF Mono, Monaco, monospace"
                font.pixelSize: {
                    if (isDefaultState) return 14
                        if (isMediaOnly) return 13
                            return 13
                }
                font.weight: {
                    if (isSystemActive) return Font.Bold
                        if (isSystemCompleted) return Font.DemiBold
                            return Font.Medium
                }
                font.letterSpacing: 0.5
                color: {
                    if (isInstalling) return "#E8F4FD"
                        if (isUninstalling) return "#FDE8E8"
                            if (isInstalled) return "#E8F5E8"
                                if (isUninstalled) return "#FDF4E8"
                                    if (isMediaOnly) return "#F4E8FD"
                                        if (isDefaultState) return "#E0E0E0"
                                            return "#FFFFFF"
                }

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
                antialiasing: true

                onTextChanged: {
                    textWrapper.opacity = 0.0;
                    fadeInTimer.start();
                }
            }
        }




        // Enhanced pulse animation with modern easing
        SequentialAnimation {
            id: pulseAnimation
            running: root.showPulse
            loops: 1

            ParallelAnimation {
                ScaleAnimator {
                    target: background
                    from: 1.0
                    to: 1.05
                    duration: 200
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: background
                    property: "opacity"
                    from: 0.95
                    to: 1.0
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            PauseAnimation { duration: 100 }
            ParallelAnimation {
                ScaleAnimator {
                    target: background
                    from: 1.05
                    to: 1.0
                    duration: 300
                    easing.type: Easing.InOutCubic
                }
                NumberAnimation {
                    target: background
                    property: "opacity"
                    from: 1.0
                    to: 0.95
                    duration: 300
                    easing.type: Easing.InOutCubic
                }
            }
            onFinished: root.showPulse = false
        }

        // Subtle breathing animation for active states
        SequentialAnimation {
            running: (isInstalling || isUninstalling) && !root.showPulse
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

        // Smooth width transition
        Behavior on width {
            NumberAnimation {
                duration: 400;
                easing.type: Easing.OutCubic
            }
        }



        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }


    // System info functions
    function updateSystemInfo() {
        // Simulate system load (replace with actual system monitoring)
        systemLoad = Math.random() * 0.8 + 0.1
        temperature = Math.floor(Math.random() * 30) + 35
        networkSpeed = Math.floor(Math.random() * 1000)
    }


    // File reading functions
    function readStatusFile() {
        var xhr = new XMLHttpRequest()
        xhr.open('GET', 'file://' + statusFile, true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200 || xhr.status === 0) {
                    var content = xhr.responseText.trim()
                    if (content !== statusText) {
                        var oldStatus = statusText
                        statusText = content
                        if (oldStatus !== statusText && content !== "") {
                            showPulse = true
                        }
                    }
                }
            }
        }
        xhr.send()
    }

    function readMediaFile() {
        var xhr = new XMLHttpRequest()
        xhr.open('GET', 'file://' + mediaFile, true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200 || xhr.status === 0) {
                    var content = xhr.responseText.trim()
                    if (content !== mediaText) {
                        mediaText = content
                    }
                }
            }
        }
        xhr.send()
    }

    // Enhanced display logic with better prioritization
    function getDisplayText() {
        // Priority 1: Active system operations
        if (isInstalling || isUninstalling) {
            return formatStatusText(statusText)
        }

        // Priority 2: Recently completed operations
        if (isInstalled || isUninstalled) {
            return formatStatusText(statusText)
        }

        // Priority 3: Media content
        if (hasMedia && !hasStatus) {
            return formatMediaText(mediaText)
        }

        // Priority 4: Other status
        if (hasStatus) {
            return formatStatusText(statusText)
        }

        // Default professional state
        return "Hello, Arvin!"
    }


    function formatStatusText(text) {
        if (!text) return ""

            var cleanText = text.toString().trim()
            var textWithoutSymbols = cleanText.replace(/▼|●|×|✓|◆|▲/g, "").trim()
            var packageName = ""

            // Direct matches
            var installMatch = textWithoutSymbols.match(/Installing:?\s+([^\s\n]+)/i)
            if (installMatch) {
                packageName = installMatch[1]
                return "INSTALLING " + packageName.toUpperCase() + " ▼"
            }

            var downloadMatch = textWithoutSymbols.match(/Downloading:?\s+([^\s\n]+)/i)
            if (downloadMatch) {
                packageName = downloadMatch[1]
                return "DOWNLOADING " + packageName.toUpperCase() + " ●"
            }

            var removeMatch = textWithoutSymbols.match(/(?:Uninstalling|Removing):?\s+([^\s\n]+)/i)
            if (removeMatch) {
                packageName = removeMatch[1]
                return "REMOVING " + packageName.toUpperCase() + " ×"
            }

            var installedMatch = textWithoutSymbols.match(/(?:Installed:?\s+([^\s\n]+)|([^\s\n]+)\s+installed)/i)
            if (installedMatch) {
                packageName = installedMatch[1] || installedMatch[2]
                return packageName.toUpperCase() + " INSTALLED ✓"
            }

            // Pacman-style log match
            var endMatch = text.match(/(?:\(\s*\d+\/\d+\)\s+)?(installing|downloading|uninstalling|removing|installed)\s+([a-zA-Z0-9._+-]+)/i)
            if (endMatch) {
                var operation = endMatch[1].toLowerCase()
                packageName = endMatch[2]

                if (operation === "installing" || operation === "downloading") {
                    return "INSTALLING " + packageName.toUpperCase() + " ▼"
                } else if (operation === "removing" || operation === "uninstalling") {
                    return "REMOVING " + packageName.toUpperCase() + " ×"
                } else if (operation === "installed") {
                    return packageName.toUpperCase() + " INSTALLED ✓"
                }
            }

            // Fallbacks
            if (cleanText.toLowerCase().includes("installing")) {
                return "INSTALLING PACKAGE ▼"
            } else if (cleanText.toLowerCase().includes("downloading")) {
                return "DOWNLOADING CONTENT ●"
            } else if (cleanText.toLowerCase().includes("uninstalling") || cleanText.toLowerCase().includes("removing")) {
                return "REMOVING PACKAGE ×"
            } else if (cleanText.toLowerCase().includes("installed")) {
                return "INSTALLATION COMPLETE ✓"
            } else if (cleanText.toLowerCase().includes("upgrade")) {
                return "SYSTEM UPDATING ◆"
            }

            return cleanText.toUpperCase()
    }


     function formatMediaText(text) {
         if (!text) return ""

             var cleanText = text.toString().trim()

             // Enhanced media formatting with masculine symbols
             if (cleanText.includes(" - ") && !cleanText.includes("♫") && !cleanText.includes("♪")) {
                 return "♫ " + cleanText
             }

             if (cleanText.includes("♫") || cleanText.includes("♪")) {
                 return cleanText
             }

             return cleanText.toUpperCase()
     }

     function updateMediaInfo(sourceName, data) {
         try {
             var playbackStatus = data["PlaybackStatus"] || ""
             var isPlaying = playbackStatus === "Playing"

             if (!isPlaying && activePlayer === sourceName) {
                 activePlayer = ""
                 return
             }
             if (!isPlaying) return

                 var metadata = data["Metadata"] || {}
                 var artist = metadata["xesam:artist"] || metadata["xesam:albumArtist"] || ""
                 var title = metadata["xesam:title"] || ""

                 if (Array.isArray(artist) && artist.length > 0) artist = artist[0]

                     if (title) {
                         var mediaInfo = artist ? artist + " - " + title : title
                         var formattedInfo = formatMediaText(mediaInfo)
                         activePlayer = sourceName
                         if (formattedInfo !== mediaText) {
                             mediaText = formattedInfo
                         }

                     }
         } catch (e) {
             console.log("Error updating media info:", e)
         }
     }

     // Auto-hide timer for completed operations
     Timer {
         id: autoHideTimer
         interval: 3000
         repeat: false
         onTriggered: {
             if (isInstalled || isUninstalled) {
                 statusText = ""
             }
         }
     }




     Component.onCompleted: {
         console.log("=== Enhanced Dynamic Island Widget Initialized ===")
         console.log("Home directory:", homeDirectory)
         console.log("Status file:", statusFile)
         console.log("Media file:", mediaFile)

         readStatusFile()
         readMediaFile()
         mprisSource.connectAllSources()
         updateSystemInfo()
         currentTime = new Date().toLocaleTimeString(Qt.locale(), "hh:mm")
         updateAnimatedWidth()
     }


}

