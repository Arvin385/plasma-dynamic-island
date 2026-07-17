import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1 as Platform
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.private.mpris as Mpris
import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasma5support as P5Support
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
    // Smoothed LLM pill suffix — avoids choppy width from tok/s flicker
    property real pillLlmTps: 0
    property string pillLlmPhase: "idle" // idle | processing
    property string pillLlmModel: ""
    // Staged text: grow expands first, then commits; shrink commits text first
    property string visibleDisplayText: ""
    property string pendingDisplayText: ""
    property bool awaitingGrowCommit: false

    // v1.3 structured caches
    property var sysData: ({})
    property var mediaData: ({})
    property var installData: ({})
    property var llmData: ({})
    property string userSticky: ""
    property color accentGreen: "#3DDC97"

    readonly property bool mediaModeActive: {
        // Live MPRIS wins; paused/stopped leaves media mode until play resumes
        var player = mprisModel.currentPlayer
        if (player)
            return player.playbackStatus === Mpris.PlaybackStatus.Playing
        return !!(mediaData && mediaData.playing === true)
    }
    readonly property bool installModeActive: {
        if (!installData || !installData.action || installData.action === "none") {
            return isInstalling || isUninstalling || isInstalled || isUninstalled
        }
        var completedAt = Number(installData.completed_at || 0)
        if (completedAt > 0) {
            var now = Date.now() / 1000
            return (now - completedAt) <= 5
        }
        return true
    }
    readonly property bool llmModeActive: !!(llmData && (llmData.model || llmData.loaded))

    readonly property string defaultPriority: {
        if (installModeActive) return "install"
        if (mediaModeActive) return "media"
        if (llmModeActive) return "llm"
        return "idle"
    }

    readonly property string priorityMode: {
        if (userSticky === "install" && installModeActive) return "install"
        if (userSticky === "media" && mediaModeActive) return "media"
        if (userSticky === "llm" && llmModeActive) return "llm"
        if (userSticky === "system") return "system"
        return defaultPriority
    }

    function setPriority(mode) { userSticky = mode }

    function activateInstallTerminal() {
        var term = Number((installData && installData.terminal_pid) || 0)
        var pid = Number((installData && installData.pid) || 0)
        var target = term > 0 ? term : pid
        if (target > 0)
            execSource.exec(homeDirectory + "/.local/bin/di-activate-pid.sh " + target)
    }

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        function exec(cmd) {
            connectSource(cmd)
        }
        onNewData: function (sourceName) {
            disconnectSource(sourceName)
        }
    }

    // Normalized lowercase version of statusText (legacy fallback)
    property string cleanStatusText: statusText.toString().toLowerCase().trim()

    // Prefer structured install JSON; fall back to legacy statusText symbols
    readonly property string installAction: {
        if (installData && installData.action && installData.action !== "none")
            return String(installData.action).toLowerCase()
        return ""
    }

    property bool isInstalling: {
        if (installAction.indexOf("install") >= 0 && installAction.indexOf("installed") < 0)
            return true
        if (installAction.indexOf("download") >= 0)
            return true
        return cleanStatusText.includes("installing") || cleanStatusText.includes("downloading")
            || statusText.includes("▼") || statusText.includes("●")
    }
    property bool isUninstalling: {
        if (installAction.indexOf("remov") >= 0 || installAction.indexOf("uninstall") >= 0)
            return true
        return cleanStatusText.includes("uninstalling") || cleanStatusText.includes("removing")
            || statusText.includes("×")
    }
    property bool isInstalled: {
        if (installAction === "installed")
            return true
        return cleanStatusText.includes("installed") || cleanStatusText.includes("downloaded")
            || cleanStatusText.includes("✓") || cleanStatusText.includes("completed")
    }
    property bool isUninstalled: {
        if (installAction === "removed")
            return true
        return cleanStatusText.includes("uninstalled") || cleanStatusText.includes("removed")
    }

    property bool isSystemActive: isInstalling || isUninstalling
    property bool isSystemCompleted: isInstalled || isUninstalled

    // Visualizer only when the pill is actually showing media (not install/llm)
    property bool isMediaOnly: mediaModeActive && priorityMode === "media"
        && !isSystemActive && !isSystemCompleted

    property bool hasMedia: mediaModeActive && mediaText !== ""
    property bool hasStatus: statusText !== "" || installModeActive || llmModeActive
    property bool hasContent: hasMedia || hasStatus || installModeActive || llmModeActive
        || priorityMode === "system"
    property bool isDefaultState: priorityMode === "idle" && !hasMedia && !installModeActive && !llmModeActive

    // Desired label (may wait for grow animation before becoming visible)
    readonly property string desiredDisplayText: {
        var _status = statusText
        var _media = mediaText
        var _prio = priorityMode
        var _sys = sysData
        var _md = mediaData
        var _ins = installData
        var _llm = llmData
        var _playing = mediaModeActive
        var _llmPhase = pillLlmPhase
        var _llmTps = pillLlmTps
        var _llmModel = pillLlmModel
        return getDisplayText()
    }
    // Back-compat alias used by width metrics / older call sites
    readonly property string currentDisplayText: desiredDisplayText

    // 0=default, 1=installing, 2=uninstalling, 3=installed, 4=uninstalled, 5=media
    property int currentState: {
        if (isInstalling) return 1
        if (isUninstalling) return 2
        if (isInstalled) return 3
        if (isUninstalled) return 4
        if (mediaModeActive && !isSystemActive) return 5
        return 0
    }


    // File paths
    property string homeDirectory: Platform.StandardPaths.writableLocation(Platform.StandardPaths.HomeLocation).toString().replace("file://", "")
    property string statusFile: homeDirectory + "/.cache/dynamic-island-status.txt"
    property string mediaFile: homeDirectory + "/.cache/dynamic-island-media.txt"
    property string sysJsonFile: homeDirectory + "/.cache/dynamic-island-sys.json"
    property string mediaJsonFile: homeDirectory + "/.cache/dynamic-island-media.json"
    property string installJsonFile: homeDirectory + "/.cache/dynamic-island-install.json"
    property string llmJsonFile: homeDirectory + "/.cache/dynamic-island-llm.json"

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

    // Panel shows the pill; hover opens fullRepresentation as a popup beyond the bar
    preferredRepresentation: compactRepresentation
    // Keep full rep in popup (never squeeze into panel)
    switchWidth: 10000
    switchHeight: 10000
    activationTogglesExpanded: false
    hideOnWindowDeactivate: false
    // Transparent Plasma popup — floating cards provide their own color
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function openExpanded() {
        collapseGraceTimer.stop()
        expanded = true
    }

    function scheduleCollapse() {
        collapseGraceTimer.restart()
    }

    function cancelCollapse() {
        collapseGraceTimer.stop()
    }

    Timer {
        id: collapseGraceTimer
        interval: 400
        repeat: false
        onTriggered: root.expanded = false
    }

    readonly property int widthAnimMs: 520

    Timer {
        id: contentTransitionTimer
        interval: 90
        repeat: false
        onTriggered: root.runContentTransition()
    }

    // After grow animation finishes, commit the new text
    Timer {
        id: growCommitTimer
        interval: root.widthAnimMs
        repeat: false
        onTriggered: root.commitGrowText()
    }

    // Measure unconstrained text (same font as the label) — always the *desired* string
    TextMetrics {
        id: widthMetrics
        text: root.desiredDisplayText
        font.family: root.uiFont
        font.pixelSize: 14
        font.weight: Font.Medium
        font.letterSpacing: 0.3

        onWidthChanged: root.scheduleContentTransition()
        onTextChanged: root.scheduleContentTransition()
    }

    // Probe for stable LLM width (processing ↔ tok/s shouldn't resize the pill)
    TextMetrics {
        id: llmWidthProbe
        font.family: root.uiFont
        font.pixelSize: 14
        font.weight: Font.Medium
        font.letterSpacing: 0.3
    }

    Behavior on animatedWidth {
        id: widthBehavior
        enabled: true
        NumberAnimation {
            duration: root.widthAnimMs
            easing.type: Easing.InOutCubic
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

    function measureDisplayText(str) {
        llmWidthProbe.text = str || ""
        return llmWidthProbe.width
    }

    function widthForDisplayText(displayText) {
        var textW = measureDisplayText(displayText)

        if (priorityMode === "llm" && pillLlmModel) {
            var base = pillLlmModel + " · "
            var wProc = measureDisplayText(base + "processing")
            var wTok = measureDisplayText(base + "999.9 tok/s")
            var wIdle = measureDisplayText(base + "idle")
            if (pillLlmPhase === "idle")
                textW = Math.max(textW, wIdle)
            else
                textW = Math.max(textW, wProc, wTok)
        }

        if (textW <= 0)
            return isDefaultState ? 200 : minWidth

        var comfort = isDefaultState ? 28 : 12
        var total = textW + islandChromeWidth() + comfort
        return Math.round(Math.min(Math.max(total, minWidth), maxWidth))
    }

    function calculateTargetWidth() {
        return widthForDisplayText(desiredDisplayText)
    }

    function scheduleContentTransition() {
        if (!contentTransitionTimer)
            return
        contentTransitionTimer.restart()
    }

    function scheduleIslandWidthSync() {
        scheduleContentTransition()
    }

    function commitVisibleText(text) {
        if (visibleDisplayText === text)
            return
        visibleDisplayText = text
    }

    function commitGrowText() {
        if (!awaitingGrowCommit)
            return
        awaitingGrowCommit = false
        commitVisibleText(pendingDisplayText)
    }

    function runContentTransition() {
        var next = desiredDisplayText
        pendingDisplayText = next
        var target = widthForDisplayText(next)

        var grow = target > animatedWidth + 12
        var shrink = target < animatedWidth - 12

        if (grow) {
            // Expand first, keep old text until width lands
            awaitingGrowCommit = true
            lastTargetWidth = target
            animatedWidth = target
            if (growCommitTimer)
                growCommitTimer.restart()
            return
        }

        // Shrink or same-size: text first, then width (shrink path you like)
        awaitingGrowCommit = false
        if (growCommitTimer)
            growCommitTimer.stop()
        commitVisibleText(next)

        if (!shrink && Math.abs(target - lastTargetWidth) < 12 && Math.abs(target - animatedWidth) < 12)
            return
        lastTargetWidth = target
        animatedWidth = target
    }

    function applyIslandWidth() {
        runContentTransition()
    }

    function syncIslandWidth() { scheduleContentTransition() }

    function updatePillLlmDisplay(o) {
        if (!o) {
            pillLlmModel = ""
            pillLlmPhase = "idle"
            pillLlmTps = 0
            return
        }
        var model = String(o.model || "")
        var phase = String(o.phase || "idle")
        var tps = Number(o.tokens_per_second || 0)
        pillLlmModel = model

        if (phase === "idle") {
            pillLlmPhase = "idle"
            pillLlmTps = 0
            return
        }

        pillLlmPhase = "processing"
        // Only move the displayed rate when it changes meaningfully
        if (tps > 0) {
            if (pillLlmTps <= 0 || Math.abs(tps - pillLlmTps) >= 1.5)
                pillLlmTps = Math.round(tps * 10) / 10
        } else {
            pillLlmTps = 0
        }
    }

    // Aliases used by older call sites
    function updateAnimatedWidth() { syncIslandWidth() }
    function startWidthMeasurement() { syncIslandWidth() }
    function applyMeasuredTextWidth(textWidth) { syncIslandWidth() }

    onStatusTextChanged: {
        scheduleContentTransition()
        if (isInstalled || isUninstalled)
            autoHideTimer.restart()
        else
            autoHideTimer.stop()
    }
    onMediaTextChanged: scheduleContentTransition()
    onShowSystemInfoChanged: scheduleContentTransition()
    onIsMediaOnlyChanged: scheduleContentTransition()
    onIsDefaultStateChanged: scheduleContentTransition()
    onDesiredDisplayTextChanged: scheduleContentTransition()
    onPriorityModeChanged: scheduleContentTransition()
    onPillLlmPhaseChanged: scheduleContentTransition()
    onPillLlmTpsChanged: scheduleContentTransition()

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
        interval: 150
        running: true
        repeat: true
        onTriggered: {
            readStatusFile()
            readMediaFile()
            readJsonCaches()
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
        if (!player) {
            if (activePlayer !== "") {
                activePlayer = ""
                playerIdentity = ""
                playerPid = 0
                mediaText = ""
            }
            return
        }

        // Paused / stopped → leave media mode until playback resumes
        if (player.playbackStatus !== Mpris.PlaybackStatus.Playing) {
            if (activePlayer !== "" || mediaText !== "") {
                activePlayer = ""
                playerIdentity = ""
                playerPid = 0
                mediaText = ""
            }
            if (mediaData && mediaData.playing === true)
                mediaData = Object.assign({}, mediaData, { playing: false })
            if (userSticky === "media")
                userSticky = ""
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

    function activateSystemMonitor() {
        // Open default terminal running htop, else top
        var cmd = "bash -lc '" +
            "MON=$(command -v htop || command -v top); " +
            "if command -v konsole >/dev/null; then konsole -e $MON; " +
            "elif command -v kitty >/dev/null; then kitty -e $MON; " +
            "elif command -v alacritty >/dev/null; then alacritty -e $MON; " +
            "elif command -v ghostty >/dev/null; then ghostty -e $MON; " +
            "elif command -v foot >/dev/null; then foot $MON; " +
            "elif command -v xdg-terminal-exec >/dev/null; then xdg-terminal-exec $MON; " +
            "else $MON; fi'"
        execSource.exec(cmd)
    }

    function raiseTaskMatching(needles) {
        var i, j, idx, hay, name, appId, desk
        for (i = 0; i < tasksModel.count; i++) {
            idx = tasksModel.index(i, 0)
            if (!tasksModel.data(idx, TaskManager.AbstractTasksModel.IsWindow))
                continue
            name = (tasksModel.data(idx, Qt.DisplayRole)
                || tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName)
                || "").toString().toLowerCase()
            appId = (tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId) || "").toString().toLowerCase()
            desk = (tasksModel.data(idx, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon)
                || "").toString().toLowerCase()
            hay = name + " " + appId + " " + desk
            for (j = 0; j < needles.length; j++) {
                if (hay.indexOf(needles[j]) >= 0) {
                    tasksModel.requestActivate(idx)
                    return true
                }
            }
        }
        return false
    }

    function activateLlmRunner() {
        var runner = String((llmData && llmData.runner) || "").toLowerCase()
        var activate = homeDirectory + "/.local/bin/di-activate-pid.sh"

        if (runner === "ollama") {
            if (raiseTaskMatching(["ollama"]))
                return
            var ollamaCmd = "bash -lc '" +
                "PID=$(pgrep -x ollama | head -1); " +
                "if [ -n \"$PID\" ] && [ -x \"" + activate + "\" ]; then \"" + activate + "\" \"$PID\"; fi; " +
                "DESK=$(find \"$HOME\"/.local/share/applications /usr/share/applications " +
                "  -iname \"*ollama*.desktop\" 2>/dev/null | head -1); " +
                "if [ -n \"$DESK\" ]; then " +
                "  if command -v gtk-launch >/dev/null; then gtk-launch \"$(basename \"$DESK\" .desktop)\"; " +
                "  else gio launch \"$DESK\" 2>/dev/null || xdg-open \"$DESK\"; fi; " +
                "  exit 0; fi; " +
                "if command -v ollama >/dev/null; then " +
                "  if command -v konsole >/dev/null; then konsole -e ollama list; " +
                "  elif command -v kitty >/dev/null; then kitty -e ollama list; " +
                "  else ollama list; fi; fi'"
            execSource.exec(ollamaCmd)
            return
        }

        // Default / lmstudio
        if (raiseTaskMatching(["lm studio", "lm-studio", "lmstudio"]))
            return
        var lmsCmd = "bash -lc '" +
            "PID=$(pgrep -f \"LM-Studio|lmstudio\" 2>/dev/null | head -1); " +
            "if [ -n \"$PID\" ] && [ -x \"" + activate + "\" ]; then \"" + activate + "\" \"$PID\"; exit 0; fi; " +
            "DESK=$(find \"$HOME\"/.local/share/applications /usr/share/applications " +
            "  -iname \"*lm*studio*.desktop\" 2>/dev/null | head -1); " +
            "if [ -n \"$DESK\" ]; then " +
            "  if command -v gtk-launch >/dev/null; then gtk-launch \"$(basename \"$DESK\" .desktop)\"; " +
            "  else gio launch \"$DESK\" 2>/dev/null || xdg-open \"$DESK\"; fi; " +
            "  exit 0; fi; " +
            "APP=$(find \"$HOME\"/Desktop \"$HOME\"/.local/bin \"$HOME\"/Applications /opt " +
            "  -maxdepth 2 \\( -iname \"LM*Studio*.AppImage\" -o -iname \"lm-studio*.AppImage\" \\) " +
            "  2>/dev/null | head -1); " +
            "if [ -n \"$APP\" ]; then nohup \"$APP\" >/dev/null 2>&1 & exit 0; fi; " +
            "command -v notify-send >/dev/null && notify-send \"Dynamic Island\" " +
            "  \"Open LM Studio from your application menu\" || true'"
        execSource.exec(lmsCmd)
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

    // Backup poll — nested MPRIS property signals are easy to miss
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: syncMprisPlayer()
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

    compactRepresentation: Item {
        id: mainContainer
        Layout.fillWidth: false
        Layout.fillHeight: false
        Layout.preferredWidth: root.animatedWidth
        Layout.preferredHeight: root.fixedHeight
        Layout.minimumWidth: root.minWidth
        Layout.maximumWidth: root.maxWidth
        Layout.minimumHeight: root.fixedHeight
        Layout.maximumHeight: root.fixedHeight
        width: root.animatedWidth
        height: root.fixedHeight

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
                if (root.priorityMode === "install") {
                    var a = String((root.installData && root.installData.action) || "")
                    if (a.indexOf("remov") >= 0 || a.indexOf("uninstall") >= 0)
                        return Qt.rgba(0.75, 0.25, 0.15, 1.0)
                    if (a.indexOf("installed") >= 0 || a.indexOf("removed") >= 0)
                        return Qt.rgba(0.15, 0.55, 0.25, 1.0)
                    return Qt.rgba(0.12, 0.35, 0.65, 1.0)
                }
                if (root.priorityMode === "media") return Qt.rgba(0.4, 0.2, 0.5, 1.0)
                if (root.priorityMode === "llm") return Qt.rgba(0.15, 0.35, 0.4, 1.0)
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

                onEntered: {
                    background.hovered = true
                    root.openExpanded()
                }
                onExited: {
                    background.hovered = false
                    root.scheduleCollapse()
                }

                onClicked: {
                    if (root.priorityMode === "install")
                        root.activateInstallTerminal()
                    else if (root.priorityMode === "media")
                        root.activateMediaPlayer()
                    else if (root.priorityMode === "system" || root.priorityMode === "idle")
                        root.activateSystemMonitor()
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

        // Install/uninstall progress — inset track + sliding thumb (stays inside pill caps)
        Item {
            id: progressTrack
            anchors.left: background.left
            anchors.right: background.right
            anchors.bottom: background.bottom
            // Inset past the stadium end-caps so the bar never bleeds out the sides
            anchors.leftMargin: Math.max(background.height * 0.5, 18)
            anchors.rightMargin: Math.max(background.height * 0.5, 18)
            anchors.bottomMargin: 6
            height: 3
            z: 4
            visible: opacity > 0.01
            opacity: (isInstalling || isUninstalling) ? 1 : 0
            clip: true

            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            readonly property bool removing: {
                if (isUninstalling) return true
                var a = String((root.installData && root.installData.action) || "")
                return a.indexOf("remov") >= 0 || a.indexOf("uninstall") >= 0
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
                x: progressTrack.sweep * Math.max(0, parent.width - width)
                color: progressTrack.accent
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
                running: progressTrack.opacity > 0.5
                loops: Animation.Infinite
                NumberAnimation {
                    target: progressTrack
                    property: "sweep"
                    from: 0
                    to: 1
                    duration: 1100
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: progressTrack
                    property: "sweep"
                    from: 1
                    to: 0
                    duration: 1100
                    easing.type: Easing.InOutSine
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
                text: root.visibleDisplayText
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

        // Smooth width transition (match root animatedWidth easing)
        Behavior on width {
            NumberAnimation {
                duration: 520
                easing.type: Easing.InOutCubic
            }
        }



        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // Popup must grow to fit every active card (dense layout + tall preferred height)
    fullRepresentation: Item {
        id: expandedContainer

        readonly property int contentH: Math.max(expandedView.implicitHeight + 10, 160)

        implicitWidth: 420
        implicitHeight: contentH
        Layout.minimumWidth: 400
        Layout.preferredWidth: 420
        Layout.maximumWidth: 480
        Layout.minimumHeight: contentH
        Layout.preferredHeight: contentH
        Layout.maximumHeight: 2400

        width: 420
        height: contentH

        ExpandedView {
            id: expandedView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            islandRoot: root
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
        // Cache is fallback only — never resurrect paused/stopped media
        if (activePlayer !== "")
            return
        if (mprisModel.currentPlayer)
            return
        if (mediaData && mediaData.playing !== true) {
            if (mediaText !== "")
                mediaText = ""
            return
        }

        var xhr = new XMLHttpRequest()
        xhr.open('GET', 'file://' + mediaFile, true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200 || xhr.status === 0) {
                    var content = xhr.responseText.trim()
                    if (!content) {
                        if (mediaText !== "")
                            mediaText = ""
                        return
                    }
                    if (content !== mediaText)
                        mediaText = content
                }
            }
        }
        xhr.send()
    }

    // Enhanced display logic with priority-mode pill content
    function getDisplayText() {
        var mode = priorityMode
        if (mode === "install") {
            var a = (installData && installData.action) ? String(installData.action) : ""
            var pkg = (installData && installData.package) ? String(installData.package) : ""
            if (!pkg && statusText)
                return formatStatusText(statusText)
            if (a.indexOf("install") >= 0 && a.indexOf("installed") < 0)
                return "INSTALLING " + pkg.toUpperCase() + " ▼"
            if (a.indexOf("remov") >= 0 || a.indexOf("uninstall") >= 0)
                return "REMOVING " + pkg.toUpperCase() + " ×"
            if (a.indexOf("installed") >= 0)
                return pkg.toUpperCase() + " INSTALLED ✓"
            if (a.indexOf("removed") >= 0)
                return pkg.toUpperCase() + " REMOVED"
            return (pkg || a || "PACKAGE").toUpperCase()
        }
        if (mode === "media") {
            var t = (mediaData && mediaData.title) ? String(mediaData.title) : mediaText
            var ar = (mediaData && mediaData.artist) ? String(mediaData.artist) : ""
            if (t && ar) return "♫ " + t + " — " + ar
            if (t) return formatMediaText(t)
            return "♫ Media"
        }
        if (mode === "llm") {
            var model = pillLlmModel || ((llmData && llmData.model) ? String(llmData.model) : "LLM")
            if (pillLlmPhase === "idle")
                return model + " · idle"
            if (pillLlmTps > 0)
                return model + " · " + pillLlmTps.toFixed(1) + " tok/s"
            return model + " · processing"
        }
        // Idle: greeting on the pill. System metrics only when hovered (or System prioritized).
        if (mode === "system" && userSticky === "system") {
            var cpu = Math.round(Number((sysData && sysData.cpu) || systemLoad * 100 || 0))
            var ram = Math.round(Number((sysData && sysData.ram) || 0))
            var gpus = (sysData && sysData.gpus) ? sysData.gpus : []
            var gpuTxt = ""
            if (gpus && gpus.length) {
                for (var i = 0; i < gpus.length; ++i) {
                    if (i) gpuTxt += " "
                    gpuTxt += "GPU" + i + " " + Math.round(Number(gpus[i].util || 0)) + "%"
                }
            } else {
                gpuTxt = "GPU —"
            }
            return "CPU " + cpu + "% · RAM " + ram + "% · " + gpuTxt
        }
        return idleGreeting
    }

    function readJsonFile(path, assignFn) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + path, true)
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4)
                return
            if (!(xhr.status === 200 || xhr.status === 0))
                return
            var raw = (xhr.responseText || "").trim()
            if (!raw)
                return
            try {
                assignFn(JSON.parse(raw))
            } catch (e) { }
        }
        xhr.send()
    }

    function readJsonCaches() {
        readJsonFile(sysJsonFile, function (o) { sysData = o })
        readJsonFile(mediaJsonFile, function (o) {
            // Do not let stale cache flip playing=true over a live paused MPRIS player
            var live = mprisModel.currentPlayer
            if (live && live.playbackStatus !== Mpris.PlaybackStatus.Playing && o)
                o = Object.assign({}, o, { playing: false })
            mediaData = o
            // Only feed pill from cache while actively playing and MPRIS quiet
            if (o && o.playing && o.title && activePlayer === "" && !live)
                mediaText = o.title + (o.artist ? (" - " + o.artist) : "")
            if (!o || !o.playing) {
                if (activePlayer === "" && mediaText !== "")
                    mediaText = ""
                if (userSticky === "media")
                    userSticky = ""
            }
        })
        readJsonFile(installJsonFile, function (o) {
            installData = o
            if (userSticky === "install" && !installModeActive)
                userSticky = ""
        })
        readJsonFile(llmJsonFile, function (o) {
            llmData = o
            updatePillLlmDisplay(o)
            if (userSticky === "llm" && !llmModeActive)
                userSticky = ""
        })
        if (userSticky === "media" && !mediaModeActive)
            userSticky = ""
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

         visibleDisplayText = desiredDisplayText
         pendingDisplayText = desiredDisplayText
         lastTargetWidth = widthForDisplayText(desiredDisplayText)
         animatedWidth = lastTargetWidth
         updateAnimatedWidth()
     }


}

