# Dynamic Island — panel plasmoid + headless collector
PREFIX      ?= $(HOME)/.local
PLUGIN_ID   ?= com.arvin.dynamicisland
SRC         := dynamic-island
SHARE_DIR   ?= $(PREFIX)/share/plasma-dynamic-island
BIN_DIR     ?= $(PREFIX)/bin

.PHONY: install uninstall plasma check

check:
	@command -v kpackagetool6 >/dev/null || { \
		echo "error: kpackagetool6 not found. On Arch/Manjaro install plasma-workspace / plasma-desktop."; \
		exit 1; \
	}
	@command -v python3 >/dev/null || { \
		echo "error: python3 not found. On Arch/Manjaro: pacman -S python"; \
		exit 1; \
	}
	@command -v plasmashell >/dev/null || { \
		echo "error: plasmashell not found. Install KDE Plasma 6 first."; \
		exit 1; \
	}
	@echo "Dependencies OK (kpackagetool6, python3, plasmashell)"

install: check
	@if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx '$(PLUGIN_ID)'; then \
		kpackagetool6 -t Plasma/Applet -u "$(CURDIR)/$(SRC)"; \
	else \
		kpackagetool6 -t Plasma/Applet -i "$(CURDIR)/$(SRC)"; \
	fi
	mkdir -p "$(SHARE_DIR)/scripts" "$(BIN_DIR)" "$(HOME)/.config/autostart"
	# v1.3 collector only — do not ship legacy di-pacman-monitor.sh
	install -m 755 scripts/di-v13-collector.sh "$(SHARE_DIR)/scripts/di-v13-collector.sh"
	install -m 755 scripts/di-activate-pid.sh "$(BIN_DIR)/di-activate-pid.sh"
	install -m 644 data/plasma-dynamic-island-autostart.desktop \
		"$(HOME)/.config/autostart/plasma-dynamic-island-collector.desktop"
	@# Kill existing collectors via pidfile / exact argv (avoid pkill -f matching this shell)
	@if [ -f "$(SHARE_DIR)/collector.pid" ]; then \
		kill "$$(cat "$(SHARE_DIR)/collector.pid")" 2>/dev/null || true; \
		rm -f "$(SHARE_DIR)/collector.pid"; \
	fi
	@ps -eo pid=,args= | awk '/\/plasma-dynamic-island\/scripts\/di-v13-collector\.sh($$| )/ {print $$1}' | while read -r pid; do kill "$$pid" 2>/dev/null || true; done
	@sleep 0.2
	@nohup "$(SHARE_DIR)/scripts/di-v13-collector.sh" >/tmp/di-v13-collector.log 2>&1 </dev/null & echo $$! > "$(SHARE_DIR)/collector.pid"
	@# Soft reload — do not fail install if plasmashell replace is denied
	@plasmashell --replace >/dev/null 2>&1 </dev/null & \
		echo "Installed $(PLUGIN_ID)"; \
		echo ""; \
		echo "Add to panel: right-click panel → Add Widgets → search \"Dynamic Island\""; \
		echo "Collector log: /tmp/di-v13-collector.log"; \
		echo "Autostart: ~/.config/autostart/plasma-dynamic-island-collector.desktop"

uninstall:
	@command -v kpackagetool6 >/dev/null && kpackagetool6 -t Plasma/Applet -r "$(PLUGIN_ID)" 2>/dev/null || true
	@if [ -f "$(SHARE_DIR)/collector.pid" ]; then kill "$$(cat "$(SHARE_DIR)/collector.pid")" 2>/dev/null || true; fi
	@ps -eo pid=,args= | awk '/\/plasma-dynamic-island\/scripts\/di-v13-collector\.sh($$| )/ {print $$1}' | while read -r pid; do kill "$$pid" 2>/dev/null || true; done
	rm -rf "$(SHARE_DIR)"
	rm -f "$(BIN_DIR)/di-activate-pid.sh"
	rm -f "$(HOME)/.config/autostart/plasma-dynamic-island-collector.desktop"
	@plasmashell --replace >/dev/null 2>&1 </dev/null & \
		echo "Removed $(PLUGIN_ID), collector scripts, and autostart entry"

plasma:
	@plasmashell --replace >/dev/null 2>&1 </dev/null &
	@echo "plasmashell reload requested"
