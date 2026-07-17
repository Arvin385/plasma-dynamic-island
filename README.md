# Plasma Dynamic Island

A KDE Plasma 6 panel widget inspired by Apple’s Dynamic Island. It shows media playback and system activity (package installs, etc.) in a compact animated pill.

Built for personal use on **KDE Plasma 6 + Wayland** (Manjaro/Arch). Other setups may need tweaks.

## Features

- Live media display via Plasma MPRIS (`org.kde.plasma.private.mpris`)
- Click the island to raise / minimize the playing app (including Brave/Chrome PWAs)
- System activity from a bash monitor (pacman, pip, npm, flatpak, updates)
- Smooth width animation that fits the current text (clamped to a max width)
- Media visualizer bars, status colors, and pulse on changes

## Project layout

```
plasma-dynamic-island/
├── dynamic-island/                 # Plasma applet package
│   ├── metadata.json               # Plugin id: com.arvin.dynamicisland
│   └── contents/ui/main.qml        # UI + media/window logic
├── scripts/
│   └── di-pacman-monitor.sh        # Background status / media cache writer
├── Makefile                        # install / reload helpers
├── README.md
└── LICENSE
```

**Source of truth** is this repo. Plasma loads the installed copy under:

`~/.local/share/plasma/plasmoids/com.arvin.dynamicisland/`

After edits, run `make install` (and usually `make plasma`) so the live widget updates.

## Requirements

- KDE Plasma 6 (Wayland recommended)
- `playerctl` (optional fallback for the bash monitor)

```bash
sudo pacman -S playerctl
```

## Install

```bash
git clone https://github.com/YOUR_USERNAME/plasma-dynamic-island.git
cd plasma-dynamic-island
make install
make plasma
```

Then add **Dynamic Island Widget** to a panel (or desktop) from Plasma’s “Add Widgets” dialog.

### Make targets

| Target | What it does |
|--------|----------------|
| `make install` | Install plasmoid + scripts |
| `make install-plasmoid` | Install applet only |
| `make install-scripts` | Install scripts only |
| `make plasma` | Restart plasmashell in the background |
| `make uninstall` | Remove installed plasmoid + scripts |
| `make print-paths` | Show resolved install paths |
| `make help` | List targets and variables |

### Configurable paths

Defaults:

- Plasmoid: `~/.local/share/plasma/plasmoids/com.arvin.dynamicisland`
- Scripts: `~/.local/share/plasma-dynamic-island/scripts`

Override as needed:

```bash
make install INSTALL_DIR=/custom/path/com.arvin.dynamicisland
make install PREFIX=$HOME/.local
make print-paths
```

## Development workflow

1. Edit files in this repo (usually `dynamic-island/contents/ui/main.qml`).
2. Deploy and reload:

```bash
make install
make plasma
```

## Background monitor

The QML widget reads status/media from cache files written by the bash monitor:

- `~/.cache/dynamic-island-status.txt`
- `~/.cache/dynamic-island-media.txt`

After `make install`, run the installed script (or the repo copy) in a terminal or user service:

```bash
~/.local/share/plasma-dynamic-island/scripts/di-pacman-monitor.sh
```

Media still works from QML MPRIS without the monitor; package/system status needs the script.

## Notes

- Tested on Manjaro + Plasma 6 + Wayland
- Arch/pacman-oriented system monitoring in the bash script
- Not shipped as a `.plasmoid` archive yet — use `make install`
- If status gets stuck, clear `~/.cache/dynamic-island-status.txt`

## Author

Arvin Adeli  
CS @ University of Maryland

## License

MIT License — see [LICENSE](LICENSE).
