# AGENTS.md — Working in `plasma-dynamic-island`

Guidance for AI agents (and humans) making changes here. Read this before touching
code; several pitfalls below are easy to hit and **not** caught by the linter.

## What this repo is

A KDE **Plasma 6 panel plasmoid** (`com.arvin.dynamicisland`, v1.3) plus a **headless
collector daemon**. Two independent halves that communicate through files:

- **Widget** (`dynamic-island/`): a floating "Dynamic Island" pill that shows one of
  four modes — `system` / `media` / `install` / `llm` — and opens an expanded popup
  of four cards on hover. Click-to-focus raises the relevant app.
- **Collector** (`scripts/di-v13-collector.sh`): a shell loop that samples CPU/RAM/GPU,
  MPRIS media, package installs, and local-LLM (`llama-server`/Ollama/LM Studio) state,
  and writes JSON caches. Launched via `scripts/` + an autostart `.desktop`.

`scripts/di-activate-pid.sh` is a helper the widget shells out to in order to raise a
window by PID (used for install terminals / LLM runners).

## The data contract is the source of truth

The widget's **only** live data path is four JSON files the collector writes to
`~/.cache/`:

| File | Feeds |
|---|---|
| `dynamic-island-sys.json` | `sysData` (cpu, ram, gpus[]) |
| `dynamic-island-media.json` | `mediaData` (playing, title, artist, source, speaker) |
| `dynamic-island-install.json` | `installData` (action, package, command, pid, terminal_pid, completed_at) |
| `dynamic-island-llm.json` | `llmData` (model, runner, phase, tokens_per_second, context, ram_mb, cpu, gpu) |

Notes:
- `dynamic-island-install-last.txt` / `dynamic-island-gpu-cache.txt` are **collector-internal
  only** — the widget never reads them.
- The legacy `dynamic-island-status.txt` / `-media.txt` `.txt` path was **removed** (the
  v1.3 collector doesn't write them). Do not reintroduce `.txt` readers.
- There is **no schema check** between collector JSON and widget keys: a field rename
  silently blanks a card. If you change a collector field, update the widget readers in
  lockstep and vice versa (see `docs/REVIEW_NOTES.md` — this is a known hygiene risk).
- `installData.action` is emitted **lowercase** (`installing|removing|installed|removed|none`).
  `installAction` lowercases defensively; color logic uses the raw string — both agree today.

## Architecture after the Phase 2 refactor

`main.qml` is the **root `PlasmoidItem`** and the orchestrator: it owns all shared
mutable state and the mode/priority logic. Everything else is extracted:

```
contents/
├── code/                  # stateless JS (imported, pure functions)
│   ├── format.js          # formatMediaText()
│   ├── mode.js            # defaultPriority(), resolvePriority(), getDisplayText(mode, data)
│   └── measure.js         # islandChromeWidth(), widthForDisplayText(text, opts)
└── ui/
    ├── main.qml           # root: state + predicates + staged-width controller + wiring
    ├── ModeColors.qml     # pragma Singleton: pillColor/textColor/cardColor
    ├── qmldir             # `singleton ModeColors ModeColors.qml` (REQUIRED)
    ├── IslandPill.qml     # compactRepresentation (background+rim+texture+viz+progress+label)
    ├── FlowingRim.qml     # Canvas gradient rim
    ├── TextureOverlay.qml # grain + highlight lines
    ├── MediaVisualizer.qml# 6-bar sine visualizer
    ├── InstallProgress.qml# inset track + sliding thumb
    ├── DataPoller.qml     # filePoller + MPRIS poll/Connections; writes onto islandRoot
    ├── AppActivation.qml  # activate{SystemMonitor,MediaPlayer,LlmRunner,InstallTerminal}
    │                      #   + task-matching heuristics + own execSource
    ├── ExpandedView.qml   # the 4 hover cards
    ├── AppletCard.qml     # one card
    └── PriorityDot.qml    # card priority toggle dot
```

### Conventions that matter

- **`property var islandRoot`** is the cross-component state handle. Visual components
  and `ExpandedView`/`AppletCard` read state through it (`islandRoot.priorityMode`,
  `islandRoot.sysData`, …). Keep it reactive: read root properties in bindings, don't
  cache them.
- **`ModeColors` is a `pragma Singleton`** and MUST stay registered in
  `contents/ui/qmldir`. If the pill/cards render with wrong or no color, check the
  `qmldir` entry first. It is the single source of truth for pill bg, label, and card
  colors — don't re-inline colors in components.
- **Activation methods live on the root as delegates.** `IslandPill` and `AppletCard`
  call `islandRoot.activate*()`; the root forwards to `appActivation`. If you move the
  `activate*` functions, keep the root delegates or every caller silently breaks.
- **Pass models as props, and don't shadow ids.** In `main.qml` the models are
  `tasks2Model` / `mpris2Model` (ids deliberately differ from the components'
  `tasksModel` / `mprisModel` **props**). Child ids are NOT properties of the parent —
  `root.tasksModel` is undefined. Reference models by their id, not via `root.`.

## Validation reality — READ THIS

**There are no automated tests, and `qmllint` is weak.** It validates syntax and some
type resolution, but it does **not** catch the failure modes that actually broke this
repo during the refactor:

- ❌ **Redeclaring a built-in property.** e.g. `Rectangle { property real radius: 0 }`
  → runtime `Property value set multiple times`, and the whole component fails to load
  (cascading up as `Type X unavailable`). qmllint passed.
- ❌ **Calling a method that doesn't exist on the target.** Moving a function off the
  root while callers still do `islandRoot.activate*()` → silent no-op at runtime.
  qmllint passed.
- ❌ **Singleton / `qmldir` resolution** and general runtime type loading.

So `qmllint` clean ≠ works. The **only real validation is loading the widget in
Plasma**. Treat every QML change as "verify visually."

### Verify a change

```
qmllint dynamic-island/contents/ui/*.qml        # quick syntax/type gate (necessary, not sufficient)
kpackagetool6 -t Plasma/Applet -u "$(pwd)/dynamic-island"   # update the INSTALLED copy
make plasma                                      # reload plasmashell
```

> ⚠️ The installed copy lives in `~/.local/share/plasma/plasmoids/com.arvin.dynamicisland/`.
> Editing the repo does nothing until you re-run the `kpackagetool6 -u` update. (A full
> `make install` also (re)starts the collector; if the collector is already running, the
> two commands above are enough.)

After reload, smoke-test by hand: pill renders; hover opens all four cards; media /
install / LLM cards populate; click-to-focus works for **each** mode (music pill raises
the player, idle pill opens `htop`/`top`, LLM pill raises the runner, install pill
raises the terminal); width grow/shrink animates without flicker.

## Behavioral invariants (don't change casually)

- **`docs/PLAN.md` is the refactor plan of record.** Phases 1–2 were behavior-preserving:
  Phase 1 only removed provably-dead code; Phase 2 only moved code. Keep it that way —
  behavior changes belong in the ledger, not a "while I'm here" edit.
- **Staged-width controller** (`runContentTransition`/`commitGrowText`/`commitVisibleText`
  + `contentTransitionTimer`/`growCommitTimer`) stays on the root because it mutates
  root fields (`animatedWidth`, `visibleDisplayText`, …). It grow-expands-then-commits,
  shrink-commits-text-first. Preserve that ordering.
- **Priority model**: `install` > `media` > `llm` > `idle`, with `userSticky` override
  only honored while the underlying signal is still live. The install card holds for a
  **5s** `completed_at` wall-clock dwell.
- **Live MPRIS wins over stale cache** (`readJsonCaches` forces `playing:false` when a
  live player is paused/stopped). Keep that precedence.

## Review ledger discipline

`docs/REVIEW_NOTES.md` is a **backlog of known issues to investigate later** — not a
to-do to fix opportunistically. Rules:
- Don't silently fix ledger items in a structural refactor; if you touch one, update
  its **Status** there.
- Reference code by **symbol**, not line number (lines drift).
- New latent bugs / heuristics / hygiene notes go here with severity + suggested action,
  rather than getting patched mid-refactor.

## Quick pitfalls checklist

- Don't redeclare base-type properties (`radius`, `color`, `opacity`, `width`…).
- Child ids aren't parent properties; pass shared objects as explicit props.
- `ModeColors` needs the `qmldir` singleton entry to resolve.
- The widget only reads the four `dynamic-island-*.json` caches — never `.txt`.
- Editing the repo ≠ installed widget: re-run `kpackagetool6 -u` + `make plasma`.
- `bash -n scripts/di-v13-collector.sh` catches collector syntax errors.
