# Refactoring Plan — Plasma Dynamic Island

Three coordinated efforts, ordered so the risky/precise work happens first and the
big refactor happens last on a cleaned-up base.

| # | Effort | Nature | Depends on |
|---|--------|--------|------------|
| 1 | Remove genuinely dead code | Precision | none — do first |
| 2 | Split the monolithic `main.qml` into modules | Meticulous, high payoff | 1 (clean base) |
| 3 | Maintain a review-notes ledger | Thoughtful, ongoing | independent |

The notes ledger from **#3** is [`docs/REVIEW_NOTES.md`](REVIEW_NOTES.md). It is
populated now and is *not* a to-do list to fix in this pass — it is the backlog of
things to look at later. Phases 1–2 here only touch what is provably dead or purely
structural; anything judgment-dependent (heuristics, fake data, perf tuning) is
recorded in the ledger instead of changed.

> **Line numbers drift.** All references below are given by symbol / anchor, not by
> fixed line number, because Phase 1 removes lines. Re-locate by the named function
> or property before editing.

---

## Ground rules

- **Behavior must not change.** Phase 1 removes code that *cannot run*; Phase 2
  moves code without altering logic. Any change that could alter runtime behavior
  belongs in the ledger, not here.
- **No automated tests exist.** Validation is a manual Plasma smoke test after each
  step: `make plasma` (reload `plasmashell`), then verify the pill renders, hover
  opens the four cards, media/install/LLM cards still populate, and click-to-focus
  still works. Do not batch multiple extraction steps before one smoke test.
- **The JSON contract is the source of truth.** The live data path is the collector's
  four `dynamic-island-{sys,media,install,llm}.json` files. The legacy `.txt` path is
  vestigial and safe to remove (see evidence below).

---

## Phase 1 — Remove genuinely dead code (precision)

Each item below was verified by grep across the repo + the collector. "Dead" means
either (a) the producer no longer exists, (b) the value is never read, or (c) the
controlling flag is never set true. Items marked **simplify** keep the symbol but drop
the dead input branch, because live code still reads the symbol.

### 1.1 Legacy `.txt` data path (producer is gone)

Evidence: the v1.3 collector writes **only** the JSON caches and
`dynamic-island-install-last.txt` / `dynamic-island-gpu-cache.txt` (collector-internal).
It never writes `dynamic-island-status.txt` or `dynamic-island-media.txt`. Nothing in
the repo writes them. So every reader of them is dead.

Remove from `main.qml`:
- `statusFile`, `mediaFile` properties.
- `readStatusFile()`, `readMediaFile()` and their calls in `filePoller` +
  `Component.onCompleted`.
- `statusText` property (only ever set by the dead `readStatusFile` / cleared by
  `autoHideTimer`). Consequently:
  - `cleanStatusText` (derived from `statusText`).
  - `onStatusTextChanged` handler + `autoHideTimer` (its only job was clearing the
    dead `statusText`).
  - `formatStatusText()` (only reached via `if (!pkg && statusText)` — never true).
  - `showPulse` (set only in `readStatusFile`) and the `pulseAnimation` that consumes
    it. `showPulse` is never true → the animation never runs.
  - In `getDisplayText()`: drop the `if (!pkg && statusText) return formatStatusText(...)`
    line. In `hasStatus`: drop the `statusText !== ""` clause (keep the
    `installModeActive || llmModeActive` terms).

Simplify (keep the live JSON-based signal, drop symbol/legacy inputs):
- `isInstalling / isUninstalling / isInstalled / isUninstalled` → depend only on
  `installAction` (from JSON); delete the `cleanStatusText.includes(...)` /
  `statusText.includes("▼|●|×|✓")` fallbacks. Live consumers
  (`background.dominantColor`, `textDisplay.color`, `progressTrack`, `isMediaOnly`,
  the breathing animation) are unaffected because `installAction` already drives them.

### 1.2 Values computed but never consumed

- `hueShift` property + its `NumberAnimation` (loops 0→1 forever, `running: true`).
  No consumer anywhere (no `MultiEffect` / `layer.effect` reads it). Remove both.
  Also drop the now-unused `import QtQuick.Effects` if nothing else needs it.
- `networkSpeed` property + its assignment in `updateSystemInfo`. Never read. Remove.
- `currentTime` property, the `timeTimer` that updates it, and the `currentTime`
  assignments in `initTimer` / `Component.onCompleted`. Its only consumer is a
  commented-out Time display. Remove the property, the timer, and the assignments.
- `updateSystemInfo()` + `systemInfoTimer`: this is a `Math.random()` stub ("replace
  with actual system monitoring"). It feeds `systemLoad` (used only in the dead
  `SystemInfoRow` and a buggy idle-pill fallback), `temperature` (dead row), and
  `networkSpeed` (dead). Remove the timer + function, and remove the `systemLoad *
  100` fallback in `getDisplayText`'s idle/system branch (real CPU comes from
  `sysData.cpu`). Flag the fallback bug in the ledger before deleting.

### 1.3 UI gated by a flag that is never set

- `showSystemInfo` is never assigned `true`. Its consumers are the `SystemInfoRow`
  (CPU ▲ / temperature ◆) and the `+120` reserve in `islandChromeWidth()`. Remove the
  `SystemInfoRow` block, the `showSystemInfo` property, the `onShowSystemInfoChanged`
  handler, and the `islandChromeWidth` branch. (If we later want a real hover-metrics
  overlay, it will come from `sysData` — tracked in the ledger, not rebuilt here.)

### 1.4 Unused derived state + no-op aliases

- `currentState` (0–5 enum): defined, never referenced. Remove.
- `applyIslandWidth()`, `startWidthMeasurement()`, `applyMeasuredTextWidth()`, and the
  `currentDisplayText` alias: no callers. Remove.
- `updateAnimatedWidth()` has exactly one caller (`Component.onCompleted`) and just
  forwards to `syncIslandWidth()`; inline it and remove the alias.

### 1.5 Commented-out dead code blocks

Remove (they are superseded by live equivalents):
- shadow backgrounds (`shadowBackground` / `shadowSecondary`)
- `clickPulse` `PropertyAnimation` block
- the commented Time display `Text`
- the old commented `textDisplay` block (superseded by the live `Item { textWrapper }`)

### 1.6 Scripts / packaging / docs

- Delete `scripts/di-pacman-monitor.sh` (809 lines). It is the old collector that
  produced the now-removed `status.txt`; the Makefile already refuses to install it,
  and no live code references it.
- Collector `json_escape()`: drop the dead `if False` branch
  (`sys.stdin.read()[:-1] if False else sys.argv[1]`) → keep `sys.argv[1]`. (Behavioral
  no-op; cosmetic.)
- README line 5 (`version plasma license`) is stray/broken text — remove it.

### Phase 1 verification checklist (run before/after)

1. `grep -rn "statusText\|statusFile\|mediaFile\|formatStatusText\|showPulse\|hueShift\|networkSpeed\|currentTime\|updateSystemInfo\|showSystemInfo\|currentState\|di-pacman"` → expect **0** live hits in `dynamic-island/` and `Makefile`/`scripts` (after removal; comments in ledger excluded).
2. Confirm the collector still writes all four JSON files unchanged.
3. `make plasma`; smoke test pill render + hover cards + media + install + LLM.

---

## Phase 2 — Split `main.qml` (~1849 lines) into modules

### Design principle

`main.qml` stays the **root `PlasmoidItem`** and owns the shared mutable state
(`sysData`, `mediaData`, `installData`, `llmData`, `userSticky`, `animatedWidth`,
`visibleDisplayText`, pill-LLM smoothing fields, etc.) plus priority/mode logic,
because almost everything reads that state. Pure, stateless logic moves to **JS
modules**; visual subtrees and behavioral controllers move to **QML components**
that receive the root (or explicit props), mirroring the existing pattern already used
by `ExpandedView` / `AppletCard` (`property var islandRoot`). This keeps behavior
identical while shrinking `main.qml` to a readable orchestrator (~250–350 lines).

### Target layout

```
contents/
├── code/                      # stateless JS (Plasma convention)
│   ├── format.js              # formatMediaText()  (formatStatusText removed in P1)
│   ├── mode.js                # priority resolution, action→color mapping,
│   │                          #   getDisplayText(mode, data) builder
│   └── measure.js             # islandChromeWidth(), widthForDisplayText()
└── ui/
    ├── main.qml               # PlasmoidItem root: state + mode logic + wiring +
    │                          #   representation bindings + Component.onCompleted
    ├── ModeColors.qml         # pragma Singleton: per-mode / action colors
    │                          #   (pill bg, text, card colors — one source of truth)
    ├── DataPoller.qml         # filePoller + readJsonFile/readJsonCaches + MPRIS
    │                          #   backup poll; assigns to islandRoot fields
    ├── AppActivation.qml      # activate{SystemMonitor,MediaPlayer,LlmRunner,
    │                          #   InstallTerminal} + raiseTaskMatching /
    │                          #   findMatchingTask / isGenericBrowserLabel /
    │                          #   isBrowserPwaAppId / launchMediaSourceApp /
    │                          #   titleHintFromStatus / syncMprisPlayer
    ├── IslandPill.qml         # compactRepresentation shell: background + label +
    │                          #   pulse/breathing/width Behaviors (props: islandRoot)
    ├── FlowingRim.qml         # the Canvas gradient rim (props: dominantColor,
    │                          #   hovered, rimThickness)
    ├── TextureOverlay.qml     # grain + highlight lines (props: radius)
    ├── MediaVisualizer.qml    # the 6-bar sine visualizer (props: active)
    ├── InstallProgress.qml    # inset track + sliding sweep thumb (props: active,
    │                          #   removing)
    ├── ExpandedView.qml       # (existing — unchanged)
    ├── AppletCard.qml         # (existing — unchanged)
    └── PriorityDot.qml        # (existing — unchanged)
```

### What stays in `main.qml`

- Shared property block (trimmed of Phase-1 dead props).
- Mode predicates: `mediaModeActive`, `installModeActive`, `llmModeActive`,
  `defaultPriority`, `priorityMode`, `setPriority`, `isMediaOnly`, `hasMedia`,
  `hasStatus`, `hasContent`, `isDefaultState`.
- Staged-text width controller (`runContentTransition`, `commitGrowText`,
  `commitVisibleText`, `scheduleContentTransition`, timers) — this mutates root
  fields, so it stays on the root but can call into `measure.js`.
- Representation bindings: `compactRepresentation: IslandPill { islandRoot: root }`,
  `fullRepresentation` wrapping `ExpandedView`.
- Model instances (`tasksModel`, `mprisModel`) + `Connections`.
- `Component.onCompleted` init (trimmed).

### Property/data passing

- Visual components take `property var islandRoot` (existing convention) and read the
  fields they need. This avoids duplicating state and keeps bindings reactive.
- `AppActivation` and `DataPoller` receive `islandRoot`, plus the models/`execSource`/
  `homeDirectory` they need, either by reference to `main.qml`'s ids or as explicit
  props. Prefer explicit props for the models so the components are self-contained.
- `ModeColors` as `pragma Singleton` (register via
  `contents/ui/qmldir` with `singleton ModeColors ModeColors.qml`) so pill, cards, and
  text colors all read the same mapping.

### Migration order (lowest risk → highest, one smoke test each)

1. Add `contents/code/*.js` with the pure functions; import them in `main.qml`; delete
   the in-file copies. Verify pill text + width unchanged.
2. Add `ModeColors.qml` singleton + `qmldir`; replace the duplicated color blocks.
   Verify card/pill colors unchanged.
3. Extract leaf visual-only components with simple props:
   `MediaVisualizer`, `InstallProgress`, `TextureOverlay`, `FlowingRim`. Smoke test.
4. Extract `IslandPill` (background + label + animations) as `compactRepresentation`.
   Smoke test hover/click + animations.
5. Extract `DataPoller` then `AppActivation`. Smoke test polling + all four
   click-to-focus actions.

### Risk notes

- **Reactivity:** prefer bindings over imperative assignment when moving logic; a
  function call in a component that sets an `islandRoot` property is fine, but avoid
  breaking binding graphs the root depends on.
- **Singleton registration:** the `qmldir` entry must exist or `ModeColors` won't
  resolve; test after step 2 specifically.
- **QML can't be unit-tested here:** treat each extraction as "verify visually." If a
  step regresses, revert that step only (keep commits per-step).

---

## Phase 3 — Review-notes ledger (ongoing)

- Living document: [`docs/REVIEW_NOTES.md`](REVIEW_NOTES.md).
- Purpose: record bugs, placeholder/fake code, inefficiencies, overcomplicated or
  fragile logic, and hygiene items **to look at later** — deliberately *not* fixed in
  Phases 1–2 because they need judgment or behavior changes.
- Each entry: category, severity, location (by symbol), description, suggested action,
  status (`Open`/`Investigating`/`Resolved`).
- Phases 1–2 must **not silently fix** ledger items; if a refactor touches one, update
  its status there.

---

## Execution checklist

- [ ] Phase 1 dead-code removal + verification grep + smoke test
- [ ] Phase 2 steps 1–5 (JS modules → ModeColors → leaf visuals → IslandPill →
      DataPoller/AppActivation), smoke test each
- [ ] Populate/refresh `docs/REVIEW_NOTES.md` with anything newly discovered
- [ ] Final end-to-end smoke test (pill states, hover cards, all four activations)
