Plasma Dynamic Island (Media + System Status Widget)

A custom KDE Plasma 6 widget that mimics a Dynamic Island-style overlay, displaying real-time system activity, media playback, and background processes in a sleek and minimalist UI. Designed and built entirely using QML and Bash for Wayland-based desktop environments.

This widget was created for personal use under KDE Plasma 6 + Wayland on Manjaro Linux. It may require manual configuration depending on your system setup.

Features

Dynamic display of package installs, media playback, and system operations

Pulse animations and auto-hiding logic

Custom status parsing with priority logic

Background file polling and status updating via Bash

KDE-native look with blurred gradients and real-time visualizer

Tech Stack

QML for UI and state logic

Bash for system monitoring and file-based status communication

playerctl and MPRIS for media detection

pacman and journalctl logs for install tracking

KDE Plasma 6, Wayland, KWin, Plasma Panels

Getting Started

Clone the repo:

git clone https://github.com/YOUR_USERNAME/plasma-dynamic-island.git

Copy main.qml and the scripts/ folder to your Plasma widget folder or use it as a standalone layer using a panel spacer and window rules.

Make the Bash script executable:

chmod +x scripts/di-pacman-monitor.sh

Ensure playerctl and required dependencies are installed:

sudo pacman -S playerctl

Optional: Customize your main.qml colors, opacity, and animation settings.

Notes

Designed and tested on: KDE Plasma 6, Wayland, Manjaro Linux

Not packaged as a .plasmoid yet — manual install only

You may need to create or clear .cache/dynamic-island-status.txt manually at times

Author

Arvin Adeli CS @ University of Maryland

Built as part of a larger effort to customize my Linux environment for real-time task visibility and automation.

License

MIT License — see LICENSE file for details.
