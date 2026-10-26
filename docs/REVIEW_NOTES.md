# Review Notes — Issues to Investigate Later

This is a backlog of things found during the v1.3 code review that are **deliberately
not fixed** in the dead-code-removal / modularization phases, because fixing them
changes behavior, needs judgment, or needs a real Plasma session to verify.

Reference locations by **symbol**, not line number (lines drift as the refactor
proceeds).

Severity: 🔴 likely bug · 🟠 questionable/inefficient · 🟡 hygiene/fragile · ⚪ nice-to-have

---

## Correctness / likely bugs

### 🔴 `updateSystemInfo()` fabricates random data — placeholder never replaced
- Location: `updateSystemInfo()` (and `systemInfoTimer`).
- The function sets `systemLoad`, `temperature`, `networkSpeed` from `Math.random()`,
  with the comment *"Simulate system load (replace with actual system monitoring)"*.
- The `SystemInfoRow` that displays it is gated by `showSystemInfo` (never true), so
  users don't see fake CPU/temperature today — **but** the idle/system pill in
  `getDisplayText()` has a fallback `systemLoad * 100` that surfaces the random value
  whenever `sysData.cpu` is missing. That means the pill can show a random CPU%.
- Action: remove the random fallback; derive CPU/RAM/GPU strictly from `sysData`
  (the collector already provides real values). If a hover metrics overlay is wanted,
  build it from `sysData`, not from `systemLoad`.
- **Status:** Resolved — Phase 1 removed `updateSystemInfo()`/`systemInfoTimer` and the
  `systemLoad * 100` idle/system fallback; CPU/RAM/GPU now come strictly from `sysData`.

### 🔴 Stale data has no TTL
- Location: `readJsonCaches()` / `DataPoller`.
- If the collector process dies, the last JSON keeps rendering as if current (only the
  install card has a `completed_at <= 5s` grace). Media/LLM/System would freeze.
- Action: stamp each JSON with `ts` in the collector and grey-out / drop cards older
  than ~2–3s in the widget.

### 🔴 `di-activate-pid.sh` KWin scripting fallback is likely a no-op on Plasma 6
- Location: `di-activate-pid.sh` (the `workspace.windowList()` JS).
- Plasma 6 KWin scripting replaced the old `workspace`/`windowList()` API with the
  `Windows` model. The fallback probably does nothing; only the `kdotool` path works.
- Action: verify against Plasma 6 KWin scripting; rewrite using the `Windows` model or
  rely solely on `kdotool` and drop the deprecated JS.

### 🟠 Two inconsistent "completed" timeouts
- Location: `installModeActive` (`completed_at <= 5` wall-clock) vs the legacy
  `autoHideTimer` (3000ms) that cleared `statusText`.
- After Phase 1 the `autoHideTimer` is gone, leaving a single 5s window — confirm the
  5s hold feels right and is the intended completion-dwell behavior.
- **Status:** Resolved (code) — Phase 1 deleted the legacy `autoHideTimer`; only the
  5s `completed_at` dwell remains. Dwell timing still needs a manual Plasma smoke-test
  feel-check (no code change pending).

---

## Inefficiency

### 🟠 `filePoller` XHR-polls four `file://` caches every ~150ms
- Location: `filePoller` (interval 150) → `readJsonFile` per file.
- ~26 file reads/sec through `XMLHttpRequest`. Heavy for a panel widget.
- Action: raise the interval, or skip files whose mtime hasn't changed, or use a
  Plasma `DataSource` / filesystem watch instead of XHR.

### 🟠 Rim `Canvas` redraws at ~30fps whenever the pill is visible
- Location: `flowingRim` Timer (interval 33, `requestPaint` + full gradient rebuild).
- Runs continuously while the widget is visible, even when idle and not hovered.
- Action: gate on hover or pause when width is stable; consider a cheaper effect.

### 🟠 Collector spawns `python3` repeatedly per tick (~3/s)
- Location: `json_escape`, `read_ram`, `proc_stats_for`, `gpu_util_for_llm`,
  `llm_phase_and_gen_tps`.
- Multiple `python3` subprocess spawns every loop iteration adds steady CPU + startup
  overhead.
- Action: cache/daemonize the hot python helpers, or move per-tick work into one
  long-lived python process that loops and writes the JSON itself.

### 🟡 Redundant MPRIS polling on top of signals
- Location: the `Connections` on `mprisModel`/`currentPlayer` plus a 200ms backup
  `Timer` calling `syncMprisPlayer()`.
- Action: confirm the backup timer is actually needed; the `Connections` may cover it.

### 🟡 Many concurrent timers
- 150ms poll, 33ms rim, 40ms visualizer, 200ms mpris backup, 1s time, 2s system.
- Action: consolidate where possible during modularization (`DataPoller` can own a
  single tick and fan out).

---

## Overcomplicated / duplicated logic

### 🟠 Color decisions duplicated across four places
- Locations: `background.dominantColor`, `textDisplay.color`, `AppletCard.cardColor`,
  `ExpandedView` install card color.
- Same state (priority mode + install action) is mapped to color in several
  independent, subtly different blocks — a drift risk.
- Action: centralize in `ModeColors` singleton (Phase 2 step 2).
- **Status:** Resolved — Phase 2 step 2 moves pill bg (`pillColor`), label (`textColor`)
  and card (`cardColor`) mappings into `contents/ui/ModeColors.qml` (`pragma Singleton`,
  registered in `contents/ui/qmldir`). Colors preserved exactly; the four call sites
  (`IslandPill` background/label, `ExpandedView` cards) now read the singleton.

### 🟠 `findMatchingTask` window-matching heuristic
- ~80 lines of magic-number scoring with browser-PWA special-casing; hard to reason
  about and brittle.
- Action: document the intent, reduce magic numbers to named constants, and add a
  simpler fallback path.

### 🟡 `islandChromeWidth()` reserves 120px for `showSystemInfo`
- Flag is never true, so the reservation is dead (removed in Phase 1). If the overlay
  returns, size it from actual content, not a fixed 120.
- **Status:** Resolved — `islandChromeWidth()` now lives in `contents/code/measure.js`
  and reserves only `padding * 2` plus the `visualizerGutter` when media bars show.

---

## Fragile heuristics (collector)

### 🟡 LLM detection assumes a single `llama-server` and parses secrets from `ps`
- Location: `llm_phase_and_gen_tps` / `find_llama`.
- Only the **first** `--port` match is used; multi-instance setups are ignored.
- Skips Cursor by `"Cursor" in line` substring match.
- Reads `--api-key` from process argv (a secret) and sends it to `127.0.0.1`. Localhost
  only, but reading secrets from argv is worth a note.
- Action: support multiple ports; replace substring skips with more robust detection.

### 🟡 Provider detection by cmdline substring
- Location: `proc_stats_for` / `collect_llm` LM/Ollama patterns.
- Substring matches against `/proc/*/cmdline` break across versions and packaging.
- Action: prefer provider APIs (`lms ps --json`, Ollama `/api/...`) as primary; keep
  substring as fallback only.

### 🟡 `isBrowserPwaAppId` regex heuristic
- `^(brave|chrome|chromium)-[a-z0-9]{16,}-` is guesswork; document assumptions.

---

## Hygiene

- 🟡 `console.log` noise in production paths (`initTimer`, `Component.onCompleted`,
  `findMatchingTask`, media window logs). Gate behind a debug flag or remove.
- 🟡 `metadata.json` sets `EnabledByDefault: true` → the widget is auto-added on
  install; may surprise users. Consider `false` + manual add.
- 🟡 `X-Plasma-FormFactors` lists `"desktop"` though this is a panel pill. Verify
  desktop placement is intended.
- 🟡 README line 5 `version plasma license` is stray/broken text (removed in Phase 1).
- 🟡 No schema/contract check between collector JSON fields and the widget's expected
  keys; a field rename silently blanks a card. Action: document the JSON schema and/or
  validate on load.
- ⚪ Phase 2 placed `syncMprisPlayer()` in `DataPoller.qml` (not `AppActivation.qml`
  as the plan's component list suggested), because it writes media fields onto the root
  and is driven by the MPRIS backup poll + Connections that the plan assigns to
  `DataPoller`. Kept together for a single ingestion owner. No behavior change.
  Status: Open (informational — revisit if activation and ingestion should be split).

---

## Status legend
- **Open** — noted, not started.
- **Investigating** — looking into it.
- **Resolved** — fixed (link the commit).

Update statuses here as items are addressed; the plan phases must not silently fix
these without recording it.
