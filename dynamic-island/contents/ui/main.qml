import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1 as Platform
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.private.mpris as Mpris
import org.kde.taskmanager as TaskManager
import QtQuick.Effects

PlasmoidItem {
    id: root

    // Widget properties
    property string statusText: ""
    property string mediaText: ""
    property string activePlayer: ""
    property string playerIdentity: ""
    property bool showPulse: false
    property int padding: 20
    property int visualizerGutter: 48
    property int minWidth: 120
    property int maxWidth: 650
    property int fixedHeight: 48
    property string uiFont: "Adwaita Sans, Source Sans 3, Noto Sans, sans-serif"
    property string idleGreeting: "Hello, Arvin!"
    property int playerPid: 0
    property real systemLoad: 0.0
    property int temperature: 0
    property int networkSpeed: 0
    property string currentTime: ""
    property bool showSystemInfo: false
    property real hueShift: 0.0

    property real animatedWidth: 200
    property real lastTargetWidth: -1

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

    // Keep property deps explicit so width remeasures whenever content changes
    readonly property string currentDisplayText: {
        var _status = statusText
        var _media = mediaText
        var _installing = isInstalling
        var _uninstalling = isUninstalling
        var _installed = isInstalled
        var _uninstalled = isUninstalled
        var _hasMedia = hasMedia
        var _hasStatus = hasStatus
        return getDisplayText()
    }

    // 0=default, 1=installing, 2=uninstalling, 3=installed, 4=uninstalled, 5=media
    property int currentState: {
        if (isInstalling) return 1
        if (isUninstalling) return 2
        if (isInstalled) return 3
        if (isUninstalled) return 4
        if (isMediaOnly || (hasMedia && !isSystemActive)) return 5
        return 0
    }


    // File paths
    property string homeDirectory: Platform.StandardPaths.writableLocation(Platform.StandardPaths.HomeLocation).toString().replace("file://", "")
    property string statusFile: homeDirectory + "/.cache/dynamic-island-status.txt"
    property string mediaFile: homeDirectory + "/.cache/dynamic-island-media.txt"

    // Show widget when there's content OR in default state
    visible: hasContent || isDefaultState

    Layout.fillWidth: false
    Layout.fillHeight: false
    Layout.preferredWidth: animatedWidth
    Layout.preferredHeight: fixedHeight
    Layout.minimumWidth: minWidth
    Layout.maximumWidth: maxWidth
    Layout.minimumHeight: fixedHeight
    Layout.maximumHeight: fixedHeight

    width: animatedWidth
    height: fixedHeight

    preferredRepresentation: fullRepresentation

    // Measure unconstrained text (same font as the label)
    TextMetrics {
        id: widthMetrics
        text: root.currentDisplayText
        font.family: root.uiFont
        font.pixelSize: 14
        font.weight: Font.Medium
        font.letterSpacing: 0.3

        onWidthChanged: root.syncIslandWidth()
        onTextChanged: root.syncIslandWidth()
    }

    Behavior on animatedWidth {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    function islandChromeWidth() {
        var chrome = padding * 2
        if (isMediaOnly)
            chrome += visualizerGutter
        if (showSystemInfo)
            chrome += 120
        return chrome
    }

    function calculateTargetWidth() {
        var textW = widthMetrics.width
        if (textW <= 0)
            return isDefaultState ? 200 : minWidth

        // Small comfort inset so glyphs aren't flush against the pill edges
        var comfort = isDefaultState ? 28 : 12
        var total = textW + islandChromeWidth() + comfort
        return Math.round(Math.min(Math.max(total, minWidth), maxWidth))
    }

    function syncIslandWidth() {
        var target = calculateTargetWidth()
        if (Math.abs(target - lastTargetWidth) < 0.5)
            return
        lastTargetWidth = target
        animatedWidth = target
    }

    // Aliases used by older call sites
    function updateAnimatedWidth() { syncIslandWidth() }
    function startWidthMeasurement() { syncIslandWidth() }
    function applyMeasuredTextWidth(textWidth) { syncIslandWidth() }

    onStatusTextChanged: {
        syncIslandWidth()
        if (isInstalled || isUninstalled)
            autoHideTimer.restart()
        else
            autoHideTimer.stop()
    }
    onMediaTextChanged: syncIslandWidth()
    onShowSystemInfoChanged: syncIslandWidth()
    onIsMediaOnlyChanged: syncIslandWidth()
    onIsDefaultStateChanged: syncIslandWidth()
    onCurrentDisplayTextChanged: syncIslandWidth()

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

    // Single file poller for status + media-cache fallback
    Timer {
        id: filePoller
        interval: 250
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
        else if (name.includes("elisa"))
            Qt.openUrlExternally("elisa:")
        else if (name.includes("mpv"))
            Qt.openUrlExternally("mpv:")
        else if (name.includes("firefox"))
            Qt.openUrlExternally("firefox:")
        else if (name.includes("brave"))
            Qt.openUrlExternally("brave:")
        else if (name.includes("chromium"))
            Qt.openUrlExternally("chromium:")
        else if (name.includes("chrome"))
            Qt.openUrlExternally("google-chrome:")
        else
            Qt.openUrlExternally("application://" + (name.endsWith(".desktop") ? name : name + ".desktop"))
    }

    function syncMprisPlayer() {
        var player = mprisModel.currentPlayer
        if (!player || player.playbackStatus !== Mpris.PlaybackStatus.Playing) {
            if (activePlayer !== "") {
                activePlayer = ""
                playerIdentity = ""
                playerPid = 0
                mediaText = ""
            }
            return
        }

        var artist = player.artist || ""
        var title = player.track || ""
        if (!title)
            return

        activePlayer = player.desktopEntry || player.identity || "media"
        playerIdentity = player.identity || ""
        playerPid = player.kdePid || 0
        var mediaInfo = artist ? (artist + " - " + title) : title
        var formattedInfo = formatMediaText(mediaInfo)
        if (formattedInfo !== mediaText)
            mediaText = formattedInfo
    }

    function isGenericBrowserLabel(label) {
        var n = (label || "").toLowerCase().trim()
        var generics = [
            "brave", "brave browser", "chrome", "chromium", "google chrome",
            "firefox", "firefox developer edition", "vivaldi", "opera",
            "microsoft edge", "edge", "librewolf"
        ]
        return generics.indexOf(n) !== -1
    }

    function isBrowserPwaAppId(appId) {
        // Chrome/Brave PWAs: brave-<32hex>-Default or chrome-<32hex>-Default
        return /^(brave|chrome|chromium)-[a-z0-9]{16,}-/i.test(appId || "")
    }

    function titleHintFromStatus() {
        // Optional dynamic hint from status text: "... | App Name"
        var s = (statusText || "") + " " + (mediaText || "")
        var m = s.match(/\|\s*([^|]+)\s*$/)
        if (m && m[1] && !isGenericBrowserLabel(m[1]))
            return m[1].trim()
        return ""
    }

    function collectBrowserPwaIndexes(desktopEntry) {
        var deskLower = (desktopEntry || "").toLowerCase()
        var wantBrave = deskLower.indexOf("brave") !== -1
        var wantChrome = deskLower.indexOf("chrom") !== -1
        var matches = []

        for (var i = 0; i < tasksModel.count; i++) {
            var idx = tasksModel.index(i, 0)
            if (!tasksModel.data(idx, TaskManager.AbstractTasksModel.IsWindow))
                continue

            var appId = (tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId) || "").toString()
            if (!isBrowserPwaAppId(appId))
                continue

            var appIdLower = appId.toLowerCase()
            if (wantBrave && appIdLower.indexOf("brave") === -1)
                continue
            if (wantChrome && appIdLower.indexOf("chrom") === -1)
                continue
            // If desktop entry isn't browser-specific, keep all PWAs

            matches.push(idx)
        }
        return matches
    }

    function activateMediaPlayer() {
        var player = mprisModel.currentPlayer
        var identity = (player && player.identity) ? player.identity : playerIdentity
        var desktop = (player && player.desktopEntry) ? player.desktopEntry : activePlayer
        var pid = (player && player.kdePid) ? player.kdePid : playerPid
        var titleHint = titleHintFromStatus()

        // If MPRIS only says "Brave"/"Chrome" and exactly one matching PWA is open, that's the target
        if (!titleHint && isGenericBrowserLabel(identity)) {
            var sole = collectBrowserPwaIndexes(desktop)
            if (sole.length === 1) {
                var soleLabel = (tasksModel.data(sole[0], Qt.DisplayRole)
                    || tasksModel.data(sole[0], TaskManager.AbstractTasksModel.AppName)
                    || "").toString()
                if (soleLabel && !isGenericBrowserLabel(soleLabel))
                    titleHint = soleLabel
            }
        }

        var match = findMatchingTask(identity, desktop, pid, titleHint)
        if (!match && player && player.canRaise) {
            player.Raise()
            match = findMatchingTask(identity, desktop, pid, titleHint)
        }
        if (!match) {
            var pwas = collectBrowserPwaIndexes(desktop)
            if (pwas.length === 1)
                match = pwas[0]
        }

        if (match) {
            toggleOrActivateTask(match)
            return
        }

        if (desktop && isBrowserPwaAppId(desktop + "-")) {
            Qt.openUrlExternally("application://" + desktop + ".desktop")
            return
        }
        if (activePlayer && !isGenericBrowserLabel(activePlayer))
            launchMediaSourceApp(activePlayer)
    }

    function toggleOrActivateTask(idx) {
        var isActive = !!tasksModel.data(idx, TaskManager.AbstractTasksModel.IsActive)
        var isMinimized = !!tasksModel.data(idx, TaskManager.AbstractTasksModel.IsMinimized)
        var winTitle = tasksModel.data(idx, Qt.DisplayRole)

        // Already focused in the foreground → minimize; otherwise bring to front
        if (isActive && !isMinimized) {
            tasksModel.requestToggleMinimized(idx)
            console.log("Minimized media window:", winTitle)
        } else {
            tasksModel.requestActivate(idx)
            console.log("Activated media window:", winTitle)
        }
    }

    function findMatchingTask(identity, desktopEntry, pid, titleHint) {
        var idLower = (identity || "").toLowerCase()
        var deskLower = (desktopEntry || "").toLowerCase()
        var hintLower = (titleHint || "").toLowerCase()
        var genericId = isGenericBrowserLabel(idLower)
        var bestIndex = null
        var bestScore = 0
        var bestLastActivated = 0

        for (var i = 0; i < tasksModel.count; i++) {
            var idx = tasksModel.index(i, 0)
            var isWindow = tasksModel.data(idx, TaskManager.AbstractTasksModel.IsWindow)
            if (!isWindow)
                continue

            var appId = (tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId) || "").toString()
            var appName = (tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || "").toString()
            var display = (tasksModel.data(idx, Qt.DisplayRole) || "").toString()
            var appPid = tasksModel.data(idx, TaskManager.AbstractTasksModel.AppPid) || 0
            var demanding = !!tasksModel.data(idx, TaskManager.AbstractTasksModel.IsDemandingAttention)
            var lastActivated = tasksModel.data(idx, TaskManager.AbstractTasksModel.LastActivated) || 0
            var appIdLower = appId.toLowerCase()
            var appNameLower = appName.toLowerCase()
            var displayLower = display.toLowerCase()
            var score = 0

            // Strongest: same process as the MPRIS player
            if (pid > 0 && appPid > 0 && appPid === pid)
                score += 250

            // Dynamic title hint (from status "| App Name" or sole open PWA label)
            if (hintLower.length > 1) {
                if (displayLower === hintLower || appNameLower === hintLower)
                    score += 220
                else if (displayLower.indexOf(hintLower) !== -1 || appNameLower.indexOf(hintLower) !== -1)
                    score += 180
            }

            // Non-generic MPRIS identity matched to window title (dedicated players)
            if (!genericId && idLower.length > 0) {
                if (displayLower.indexOf(idLower) !== -1)
                    score += 120
                if (appNameLower.indexOf(idLower) !== -1)
                    score += 100
            }

            // Prefer browser PWA windows over the main browser window (structural, not app-specific)
            if (isBrowserPwaAppId(appIdLower)) {
                score += 90
                if (!isGenericBrowserLabel(displayLower) && displayLower.length > 0)
                    score += 70
                if (!isGenericBrowserLabel(appNameLower) && appNameLower.length > 0)
                    score += 50
            } else if (deskLower.indexOf("brave") !== -1 || deskLower.indexOf("chrom") !== -1) {
                if (appIdLower.indexOf("brave") !== -1 || appIdLower.indexOf("chrom") !== -1)
                    score += 5
            }

            if (demanding)
                score += 30
            if (tasksModel.data(idx, TaskManager.AbstractTasksModel.IsMinimized))
                score += 5

            if (score > bestScore
                    || (score === bestScore && score > 0 && lastActivated > bestLastActivated)) {
                bestScore = score
                bestIndex = idx
                bestLastActivated = lastActivated
            }
        }

        if (bestIndex !== null && bestScore >= 90) {
            console.log("Matched media task score:", bestScore,
                        "window:", tasksModel.data(bestIndex, Qt.DisplayRole),
                        "hint:", titleHint, "pid:", pid)
            return bestIndex
        }
        console.log("No suitable task (best:", bestScore, ") identity:", identity,
                    "hint:", titleHint, "pid:", pid)
        return null
    }

    TaskManager.TasksModel {
        id: tasksModel
        filterByVirtualDesktop: false
        filterByActivity: false
        filterMinimized: false
        filterHidden: false
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    // Plasma 6 MPRIS (replaces removed plasma5support mpris2 dataengine)
    Mpris.Mpris2Model {
        id: mprisModel
    }

    Connections {
        target: mprisModel
        function onCurrentPlayerChanged() {
            syncMprisPlayer()
        }
    }

    Connections {
        target: mprisModel.currentPlayer
        enabled: mprisModel.currentPlayer !== null
        function onTrackChanged() { syncMprisPlayer() }
        function onArtistChanged() { syncMprisPlayer() }
        function onPlaybackStatusChanged() { syncMprisPlayer() }
        function onIdentityChanged() { syncMprisPlayer() }
        function onDesktopEntryChanged() { syncMprisPlayer() }
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
            clip: true

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
                    if (currentState === 5) {
                        console.log("Media mode. Player:", activePlayer)
                        activateMediaPlayer()
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
                function onHoveredChanged() {
                    flowingRim.fhovered = background.hovered
                }
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
                if (w <= 0 || h <= 0)
                    return

                const r = h / 2 + 3
                const strokeInset = rimThickness

                ctx.translate(strokeInset, strokeInset)

                const dom = background.dominantColor
                const bright = qmlColorToRgba(Qt.lighter(dom, 2.2), 1.0)
                const mintAccent = Qt.rgba(0, 1, 0.8, 1)
                const purpAccent = Qt.rgba(0.6, 0.2, 0.9, 1)
                const goldAccent = Qt.rgba(1, 0.85, 0.3, 1)

                // Canvas addColorStop requires CSS color strings, not QColor
                const domMint = qmlColorToRgba(blendColors(dom, mintAccent, 0.2))
                const domPurp = qmlColorToRgba(blendColors(dom, purpAccent, 0.2))
                const domGold = qmlColorToRgba(blendColors(dom, goldAccent, 0.2))
                const mintPurp = qmlColorToRgba(blendColors(blendColors(dom, mintAccent, 0.2), blendColors(dom, purpAccent, 0.2), 0.4))
                const purpGold = qmlColorToRgba(blendColors(blendColors(dom, purpAccent, 0.2), blendColors(dom, goldAccent, 0.2), 0.4))

                const loopWidth = Math.max(w * 8, 1)
                const offset = gradientShift % loopWidth
                const gradient = ctx.createLinearGradient(-loopWidth + offset, 0, offset, 0)

                gradient.addColorStop(0.00, bright)
                gradient.addColorStop(0.15, domMint)
                gradient.addColorStop(0.30, bright)
                gradient.addColorStop(0.40, mintPurp)
                gradient.addColorStop(0.50, domPurp)
                gradient.addColorStop(0.60, purpGold)
                gradient.addColorStop(0.70, bright)
                gradient.addColorStop(0.85, domGold)
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
                interval: 33
                running: root.visible && root.width > 0
                repeat: true
                onTriggered: {
                    flowingRim.gradientShift += 6
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
                opacity: textureOverlay.subtleOpacity * 0.7
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
                opacity: textureOverlay.subtleOpacity * 0.7
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 0
                border.color: Qt.rgba(1, 1, 1, textureOverlay.subtleOpacity * 0.3)
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
                    font.family: root.uiFont
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
                    font.family: root.uiFont
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

        // Media visualizer — one timer, sine heights (no per-bar animation graphs)
        Row {
            id: mediaVisualizer
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16
            spacing: 3
            visible: isMediaOnly
            z: 3
            height: 22
            property real phase: 0

            Timer {
                interval: 40
                running: mediaVisualizer.visible
                repeat: true
                onTriggered: mediaVisualizer.phase += 0.18
            }

            Repeater {
                model: 6
                Rectangle {
                    width: 3
                    radius: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real barPhase: index * 0.85
                    height: 4 + 14 * (0.5 + 0.5 * Math.sin(mediaVisualizer.phase + barPhase))
                    color: Qt.hsla(((index * 38 + 265) % 360) / 360, 0.72, 0.68, 0.95)
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
                    GradientStop { position: 0.5; color: progressIndicator.color }
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
                text: root.currentDisplayText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: isMediaOnly ? (root.padding + root.visualizerGutter) : root.padding
                anchors.rightMargin: root.padding

                font.family: root.uiFont
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 0.3
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
                clip: true

                onTextChanged: {
                    textWrapper.opacity = 0.0
                    fadeInTimer.start()
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
        // Cache is fallback only — do not clobber live MPRIS
        if (activePlayer !== "")
            return

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

        // Default idle greeting
        return idleGreeting
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
         syncMprisPlayer()
         updateSystemInfo()
         currentTime = new Date().toLocaleTimeString(Qt.locale(), "hh:mm")
         updateAnimatedWidth()
     }


}

