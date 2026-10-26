// Stateless media-text formatting. Extracted from main.qml (Phase 2).
// Pure: no access to widget state, so it stays trivially testable and reactive
// bindings in QML are unaffected by moving it here.

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
