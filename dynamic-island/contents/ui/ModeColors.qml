pragma Singleton
import QtQuick 2.15

// Single source of truth for pill + card colors (Phase 2). Previously the same
// state (priority mode + install action) was mapped to color in four separate,
// subtly different blocks — background.dominantColor, textDisplay.color,
// AppletCard.cardColor and the ExpandedView install card. Centralizing them here
// removes the drift risk. Colors are preserved exactly as before.
QtObject {
    id: root

    // Pill background dominant color.
    // `rawAction` is the un-lowercased installData.action string, matching the
    // original dominantColor logic (needles are lowercase; collector emits lowercase).
    function pillColor(mode, rawAction, isInstalling, isUninstalling, isInstalled, isUninstalled, isMediaOnly) {
        if (mode === "install") {
            var a = String(rawAction || "")
            if (a.indexOf("remov") >= 0 || a.indexOf("uninstall") >= 0)
                return Qt.rgba(0.75, 0.25, 0.15, 1.0)
            if (a.indexOf("installed") >= 0 || a.indexOf("removed") >= 0)
                return Qt.rgba(0.15, 0.55, 0.25, 1.0)
            return Qt.rgba(0.12, 0.35, 0.65, 1.0)
        }
        if (mode === "media") return Qt.rgba(0.4, 0.2, 0.5, 1.0)
        if (mode === "llm") return Qt.rgba(0.15, 0.35, 0.4, 1.0)
        if (isInstalling) return Qt.rgba(0.12, 0.35, 0.65, 1.0)
        if (isUninstalling) return Qt.rgba(0.75, 0.25, 0.15, 1.0)
        if (isInstalled) return Qt.rgba(0.15, 0.55, 0.25, 1.0)
        if (isUninstalled) return Qt.rgba(0.6, 0.45, 0.15, 1.0)
        if (isMediaOnly) return Qt.rgba(0.4, 0.2, 0.5, 1.0)
        return Qt.rgba(0.08, 0.08, 0.08, 1.0)
    }

    // Pill label color.
    function textColor(isInstalling, isUninstalling, isInstalled, isUninstalled, isMediaOnly, isDefaultState) {
        if (isInstalling) return "#E8F4FD"
        if (isUninstalling) return "#FDE8E8"
        if (isInstalled) return "#E8F5E8"
        if (isUninstalled) return "#FDF4E8"
        if (isMediaOnly) return "#F4E8FD"
        if (isDefaultState) return "#E0E0E0"
        return "#FFFFFF"
    }

    // Expanded-view card color. `rawAction` only consulted for the install card.
    function cardColor(modeId, installModeActive, rawAction) {
        if (modeId === "system") return "#1E4D6B"
        if (modeId === "media") return "#5B2A7A"
        if (modeId === "llm") return "#0D5C56"
        if (modeId === "install") {
            if (!installModeActive) return "#1E4A7A"
            var a = String(rawAction || "")
            if (a.indexOf("remov") >= 0 || a.indexOf("uninstall") >= 0) return "#7A2A2A"
            if (a.indexOf("installed") >= 0 || a.indexOf("removed") >= 0) return "#2A6B45"
            return "#1E4A7A"
        }
        return "#2A5A8C"
    }
}
