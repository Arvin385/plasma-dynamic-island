// Pill width measurement helpers. Extracted from main.qml (Phase 2).
// Pure: callers supply the chrome inputs and a `measure` callback that wraps
// the widget's TextMetrics probe, so the binding graph stays on the root.

// Non-text horizontal chrome the pill reserves: padding both sides, plus the
// visualizer gutter when media bars are actually shown.
function islandChromeWidth(padding, visualizerGutter, isMediaOnly) {
    var chrome = padding * 2
    if (isMediaOnly)
        chrome += visualizerGutter
    return chrome
}

// Target pill width for a display string. `opts` carries:
//   measure (function(str) -> px), priorityMode, pillLlmModel, pillLlmPhase,
//   isDefaultState, padding, visualizerGutter, isMediaOnly, minWidth, maxWidth
function widthForDisplayText(displayText, opts) {
    var textW = opts.measure(displayText)

    // LLM: pin width to the widest suffix so tok/s flicker doesn't resize the pill.
    if (opts.priorityMode === "llm" && opts.pillLlmModel) {
        var base = opts.pillLlmModel + " · "
        var wProc = opts.measure(base + "processing")
        var wTok = opts.measure(base + "999.9 tok/s")
        var wIdle = opts.measure(base + "idle")
        if (opts.pillLlmPhase === "idle")
            textW = Math.max(textW, wIdle)
        else
            textW = Math.max(textW, wProc, wTok)
    }

    if (textW <= 0)
        return opts.isDefaultState ? 200 : opts.minWidth

    var comfort = opts.isDefaultState ? 28 : 12
    var total = textW + islandChromeWidth(opts.padding, opts.visualizerGutter, opts.isMediaOnly) + comfort
    return Math.round(Math.min(Math.max(total, opts.minWidth), opts.maxWidth))
}
