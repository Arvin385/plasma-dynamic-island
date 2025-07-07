# Plasma Dynamic Island (Media + System Status Widget)

A custom KDE Plasma 6 widget that mimics a Dynamic Island-style overlay, displaying real-time system activity, media playback, and background processes in a sleek and minimalist UI. Designed and built entirely using QML and Bash for Wayland-based desktop environments.

This widget was created for personal use under KDE Plasma 6 + Wayland on Manjaro Linux. It may require manual configuration depending on your system setup.

---

## Features

* Dynamic display of package installs, media playback, and system operations
* Pulse animations and auto-hiding logic
* Custom status parsing with priority logic
* Background file polling and status updating via Bash
* KDE-native look with blurred gradients and real-time visualizer

---

## Tech Stack

* QML for UI and state logic
* Bash for system monitoring and file-based status communication
* `playerctl` and MPRIS for media detection
* `pacman` and `journalctl` logs for install tracking
* KDE Plasma 6, Wayland, KWin, Plasma Panels

---

## Getting Started

1. **Clone the repository:**

   ```bash
   git clone https://github.com/YOUR_USERNAME/plasma-dynamic-island.git
   ```

2. **Install the widget:**

   * Copy `main.qml` and the `scripts/` folder to your Plasma widget directory.
   * Or use it as a standalone panel layer with a spacer and custom window rules.

3. **Make the Bash script executable:**

   ```bash
   chmod +x scripts/di-pacman-monitor.sh
   ```

4. **Ensure required dependencies are installed:**

   ```bash
   sudo pacman -S playerctl
   ```

5. (Optional) Customize colors, opacity, and animation in `main.qml`.

---

## Notes

* Designed and tested on: KDE Plasma 6, Wayland, Manjaro Linux
* Not currently packaged as a `.plasmoid` — manual install only
* You may need to manually create or clear `.cache/dynamic-island-status.txt` as needed

---

## Author

**Arvin Adeli**
Computer Science @ University of Maryland
Built as part of a broader project to enhance real-time visibility and automation in my Linux workflow.

---

## License

MIT License — see `LICENSE` file for full details.
