# Plasma Dynamic Island

A Dynamic Island for the **KDE Plasma 6** panel. One small widget sits in your bar and shows whatever is happening right now — a download, a song, a local AI model, your system load. Hover it to open a stack of cards. Click a card to jump straight to that thing.

version plasma license

> Works on Wayland, built and tested on Arch / Manjaro with Plasma 6.

---

## The idea

The widget is a compact label in your panel that changes with what you're doing:


| You're...                        | It shows                              |
| -------------------------------- | ------------------------------------- |
| Installing or removing a package | Package name + a progress bar         |
| Playing music or video           | Track, source, and output device      |
| Running a local model            | Model name and live generation speed  |
| Doing nothing special            | A greeting; hover for CPU / RAM / GPU |


Hover and it expands into four cards — **System**, **Media**, **Local LLM**, **Packages** — always all four, so you get the full picture at a glance.

---

## Get it running

**1. Install**

```bash
git clone https://github.com/Arvin385/plasma-dynamic-island.git
cd plasma-dynamic-island
make install
```

**2. Add it to your panel**

- Right-click the panel → **Add Widgets**
- Search **Dynamic Island**
- Drag it onto the panel

That's it. If it doesn't show up in the list immediately, run `make plasma` or log out and back in.

> **Before you start**, you need Plasma 6 with `kpackagetool6` and `python3` — both come with a standard Plasma / Manjaro install. See [Requirements](#requirements) for the optional extras.

---

## Using it

Hover to expand. Each card is clickable:


| Card          | Click opens                             |
| ------------- | --------------------------------------- |
| **System**    | A terminal running `htop` (or `top`)    |
| **Media**     | The app that's playing                  |
| **Local LLM** | The active runner — LM Studio or Ollama |
| **Packages**  | The terminal running the install        |


**Pick what the panel shows.** By default the label follows a priority — Packages → Media → LLM → System — so the most active thing wins. Click the green dot on any card to pin it there instead.

---

## Requirements

**Required** — you almost certainly already have these on Plasma:


| Component                      | Package (Arch / Manjaro)              |
| ------------------------------ | ------------------------------------- |
| KDE Plasma 6 + `kpackagetool6` | `plasma-desktop` / `plasma-workspace` |
| Python 3                       | `python`                              |


**Optional** — each one just unlocks more detail; skip any you don't want:


| Component                                                         | Enables                            |
| ----------------------------------------------------------------- | ---------------------------------- |
| `playerctl`                                                       | Media title / artist / source      |
| `gputop`                                                          | Intel / Xe GPU utilization         |
| `nvidia-smi`                                                      | NVIDIA GPU utilization             |
| `kdotool`                                                         | Stronger click-to-focus on Wayland |
| [LM Studio](https://lmstudio.ai/) / [Ollama](https://ollama.com/) | The Local LLM card                 |


Run `make check` anytime to confirm the required pieces are present.

---

## How it works

Two parts: the widget draws the UI, and a small background script feeds it data (~3 updates/sec) through cache files.

```
com.arvin.dynamicisland          the panel widget + hover cards
        ▲ reads
~/.cache/dynamic-island-{sys,media,install,llm}.json
        ▲ writes
di-v13-collector.sh              runs in the background, also on login
```


| Path                          | Role                                        |
| ----------------------------- | ------------------------------------------- |
| `dynamic-island/`             | The Plasma plasmoid (QML + metadata)        |
| `scripts/di-v13-collector.sh` | Polls system, media, package, and LLM state |
| `scripts/di-activate-pid.sh`  | Focuses a window by PID (KWin / `kdotool`)  |


`make install` handles all of this — registering the widget, starting the collector, adding a login autostart entry, and reloading Plasma.

---

## Commands


| Command          | What it does                                                            |
| ---------------- | ----------------------------------------------------------------------- |
| `make install`   | Install / upgrade, start the collector, enable autostart, reload Plasma |
| `make uninstall` | Remove the widget, scripts, and autostart entry                         |
| `make plasma`    | Reload `plasmashell`                                                    |
| `make check`     | Verify required tools are installed                                     |


---

## Troubleshooting


| Symptom                     | Check                                                                                    |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| Not in the Add Widgets list | `kpackagetool6 -t Plasma/Applet -l | grep dynamicisland`, then `make plasma` or re-login |
| Cards show no data          | `tail /tmp/di-v13-collector.log`, inspect `~/.cache/dynamic-island-*.json`               |
| No GPU reading              | Install `gputop` (Intel / Xe) or confirm `nvidia-smi` works                              |
| No tokens/sec               | Only shown while generating, with LM Studio's local server running                       |
| Collector seems dead        | Check the PID in `~/.local/share/plasma-dynamic-island/collector.pid`                    |


---

## License

MIT © Arvin Adeli. See [LICENSE](LICENSE).
