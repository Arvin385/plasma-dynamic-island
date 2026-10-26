import QtQuick 2.15
import org.kde.plasma.private.mpris as Mpris
import "../code/format.js" as Format

// Polls the four JSON caches + MPRIS and writes them onto `islandRoot`. Extracted
// from main.qml (Phase 2). Owns the filePoller tick, the MPRIS backup poll, and the
// MPRIS signal Connections; all ingestion lands on the root's shared fields so the
// root's binding graphs stay reactive.
Item {
    id: poller

    property var islandRoot
    property var mprisModel
    property string homeDirectory: ""

    readonly property string sysJsonFile: homeDirectory + "/.cache/dynamic-island-sys.json"
    readonly property string mediaJsonFile: homeDirectory + "/.cache/dynamic-island-media.json"
    readonly property string installJsonFile: homeDirectory + "/.cache/dynamic-island-install.json"
    readonly property string llmJsonFile: homeDirectory + "/.cache/dynamic-island-llm.json"

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

    function updatePillLlmDisplay(o) {
        if (!islandRoot)
            return
        if (!o) {
            islandRoot.pillLlmModel = ""
            islandRoot.pillLlmPhase = "idle"
            islandRoot.pillLlmTps = 0
            return
        }
        var model = String(o.model || "")
        var phase = String(o.phase || "idle")
        var tps = Number(o.tokens_per_second || 0)
        islandRoot.pillLlmModel = model

        if (phase === "idle") {
            islandRoot.pillLlmPhase = "idle"
            islandRoot.pillLlmTps = 0
            return
        }

        islandRoot.pillLlmPhase = "processing"
        // Only move the displayed rate when it changes meaningfully
        if (tps > 0) {
            if (islandRoot.pillLlmTps <= 0 || Math.abs(tps - islandRoot.pillLlmTps) >= 1.5)
                islandRoot.pillLlmTps = Math.round(tps * 10) / 10
        } else {
            islandRoot.pillLlmTps = 0
        }
    }

    function syncMprisPlayer() {
        if (!islandRoot)
            return
        var player = mprisModel ? mprisModel.currentPlayer : null
        if (!player) {
            if (islandRoot.activePlayer !== "") {
                islandRoot.activePlayer = ""
                islandRoot.playerIdentity = ""
                islandRoot.playerPid = 0
                islandRoot.mediaText = ""
            }
            return
        }

        // Paused / stopped → leave media mode until playback resumes
        if (player.playbackStatus !== Mpris.PlaybackStatus.Playing) {
            if (islandRoot.activePlayer !== "" || islandRoot.mediaText !== "") {
                islandRoot.activePlayer = ""
                islandRoot.playerIdentity = ""
                islandRoot.playerPid = 0
                islandRoot.mediaText = ""
            }
            if (islandRoot.mediaData && islandRoot.mediaData.playing === true)
                islandRoot.mediaData = Object.assign({}, islandRoot.mediaData, { playing: false })
            if (islandRoot.userSticky === "media")
                islandRoot.userSticky = ""
            return
        }

        var artist = player.artist || ""
        var title = player.track || ""
        if (!title)
            return

        islandRoot.activePlayer = player.desktopEntry || player.identity || "media"
        islandRoot.playerIdentity = player.identity || ""
        islandRoot.playerPid = player.kdePid || 0
        var mediaInfo = artist ? (artist + " - " + title) : title
        var formattedInfo = Format.formatMediaText(mediaInfo)
        if (formattedInfo !== islandRoot.mediaText)
            islandRoot.mediaText = formattedInfo
    }

    function readJsonCaches() {
        if (!islandRoot)
            return
        readJsonFile(sysJsonFile, function (o) { islandRoot.sysData = o })
        readJsonFile(mediaJsonFile, function (o) {
            // Do not let stale cache flip playing=true over a live paused MPRIS player
            var live = mprisModel ? mprisModel.currentPlayer : null
            if (live && live.playbackStatus !== Mpris.PlaybackStatus.Playing && o)
                o = Object.assign({}, o, { playing: false })
            islandRoot.mediaData = o
            // Only feed pill from cache while actively playing and MPRIS quiet
            if (o && o.playing && o.title && islandRoot.activePlayer === "" && !live)
                islandRoot.mediaText = o.title + (o.artist ? (" - " + o.artist) : "")
            if (!o || !o.playing) {
                if (islandRoot.activePlayer === "" && islandRoot.mediaText !== "")
                    islandRoot.mediaText = ""
                if (islandRoot.userSticky === "media")
                    islandRoot.userSticky = ""
            }
        })
        readJsonFile(installJsonFile, function (o) {
            islandRoot.installData = o
            if (islandRoot.userSticky === "install" && !islandRoot.installModeActive)
                islandRoot.userSticky = ""
        })
        readJsonFile(llmJsonFile, function (o) {
            islandRoot.llmData = o
            updatePillLlmDisplay(o)
            if (islandRoot.userSticky === "llm" && !islandRoot.llmModeActive)
                islandRoot.userSticky = ""
        })
        if (islandRoot.userSticky === "media" && !islandRoot.mediaModeActive)
            islandRoot.userSticky = ""
    }

    // Single file poller for the JSON caches + media-cache fallback
    Timer {
        id: filePoller
        interval: 150
        running: true
        repeat: true
        onTriggered: poller.readJsonCaches()
    }

    // Backup poll — nested MPRIS property signals are easy to miss
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: poller.syncMprisPlayer()
    }

    Connections {
        target: poller.mprisModel
        function onCurrentPlayerChanged() {
            poller.syncMprisPlayer()
        }
    }

    Connections {
        target: poller.mprisModel ? poller.mprisModel.currentPlayer : null
        enabled: poller.mprisModel !== null && poller.mprisModel.currentPlayer !== null
        function onTrackChanged() { poller.syncMprisPlayer() }
        function onArtistChanged() { poller.syncMprisPlayer() }
        function onPlaybackStatusChanged() { poller.syncMprisPlayer() }
        function onIdentityChanged() { poller.syncMprisPlayer() }
        function onDesktopEntryChanged() { poller.syncMprisPlayer() }
    }
}
