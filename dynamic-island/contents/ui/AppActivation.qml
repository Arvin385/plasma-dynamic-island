import QtQuick 2.15
import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasma5support as P5Support

// Click-to-focus activation + window-matching heuristics. Extracted from
// main.qml (Phase 2). Reads the current player / task state from `islandRoot`
// and the models passed in as props; owns its own exec DataSource.
Item {
    id: activator

    property var islandRoot
    property var tasksModel
    property var mprisModel
    property string homeDirectory: ""

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

    function activateInstallTerminal() {
        if (!islandRoot)
            return
        var term = Number((islandRoot.installData && islandRoot.installData.terminal_pid) || 0)
        var pid = Number((islandRoot.installData && islandRoot.installData.pid) || 0)
        var target = term > 0 ? term : pid
        if (target > 0)
            execSource.exec(homeDirectory + "/.local/bin/di-activate-pid.sh " + target)
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
        if (!islandRoot)
            return
        var runner = String((islandRoot.llmData && islandRoot.llmData.runner) || "").toLowerCase()
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
        // Optional dynamic hint from the media text: "... | App Name"
        var mt = islandRoot ? islandRoot.mediaText : ""
        var m = (mt || "").match(/\|\s*([^|]+)\s*$/)
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
        var player = mprisModel ? mprisModel.currentPlayer : null
        var identity = (player && player.identity) ? player.identity : (islandRoot ? islandRoot.playerIdentity : "")
        var desktop = (player && player.desktopEntry) ? player.desktopEntry : (islandRoot ? islandRoot.activePlayer : "")
        var pid = (player && player.kdePid) ? player.kdePid : (islandRoot ? islandRoot.playerPid : 0)
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
        if (islandRoot && islandRoot.activePlayer && !isGenericBrowserLabel(islandRoot.activePlayer))
            launchMediaSourceApp(islandRoot.activePlayer)
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
}
