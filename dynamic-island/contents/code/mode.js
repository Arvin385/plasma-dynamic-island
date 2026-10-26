// Priority resolution + pill display-text builder. Extracted from main.qml
// (Phase 2). Pure functions: callers pass in the current widget state, so the
// reactive binding graphs in main.qml stay intact (these are only called from
// inside property/function bindings that already depend on the inputs).

// Default priority when the user has not pinned a mode.
function defaultPriority(installModeActive, mediaModeActive, llmModeActive) {
    if (installModeActive) return "install"
    if (mediaModeActive) return "media"
    if (llmModeActive) return "llm"
    return "idle"
}

// Resolve the effective priority mode, honoring a sticky user selection that is
// still backed by a live signal.
function resolvePriority(userSticky, installModeActive, mediaModeActive, llmModeActive, defaultPri) {
    if (userSticky === "install" && installModeActive) return "install"
    if (userSticky === "media" && mediaModeActive) return "media"
    if (userSticky === "llm" && llmModeActive) return "llm"
    if (userSticky === "system") return "system"
    return defaultPri
}

// Build the pill label for a given mode. `d` carries the widget state:
//   installData, mediaData, mediaText, llmData,
//   pillLlmModel, pillLlmPhase, pillLlmTps,
//   sysData, userSticky, idleGreeting, formatMediaText (function)
function getDisplayText(mode, d) {
    if (mode === "install") {
        var a = (d.installData && d.installData.action) ? String(d.installData.action) : ""
        var pkg = (d.installData && d.installData.package) ? String(d.installData.package) : ""
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
        var t = (d.mediaData && d.mediaData.title) ? String(d.mediaData.title) : d.mediaText
        var ar = (d.mediaData && d.mediaData.artist) ? String(d.mediaData.artist) : ""
        if (t && ar) return "♫ " + t + " — " + ar
        if (t) return d.formatMediaText(t)
        return "♫ Media"
    }
    if (mode === "llm") {
        var model = d.pillLlmModel || ((d.llmData && d.llmData.model) ? String(d.llmData.model) : "LLM")
        if (d.pillLlmPhase === "idle")
            return model + " · idle"
        if (d.pillLlmTps > 0)
            return model + " · " + d.pillLlmTps.toFixed(1) + " tok/s"
        return model + " · processing"
    }
    // Idle: greeting on the pill. System metrics only when System is prioritized.
    if (mode === "system" && d.userSticky === "system") {
        var cpu = Math.round(Number((d.sysData && d.sysData.cpu) || 0))
        var ram = Math.round(Number((d.sysData && d.sysData.ram) || 0))
        var gpus = (d.sysData && d.sysData.gpus) ? d.sysData.gpus : []
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
    return d.idleGreeting
}
