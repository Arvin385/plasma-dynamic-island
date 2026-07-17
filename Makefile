# Plasma Dynamic Island — install helpers
#
# Usage:
#   make install
#   make install INSTALL_DIR=/custom/path/com.arvin.dynamicisland
#   make uninstall
#
# After editing QML/scripts, run `make install` then reload Plasma if needed:
#   plasmashell --replace &

PREFIX            ?= $(HOME)/.local
PLASMOID_DIR      ?= $(PREFIX)/share/plasma/plasmoids
PLUGIN_ID         ?= com.arvin.dynamicisland

# Full destination for the applet package (override this to change install location)
INSTALL_DIR       ?= $(PLASMOID_DIR)/$(PLUGIN_ID)

# Optional companion scripts (monitor daemon, etc.)
SCRIPTS_INSTALL_DIR ?= $(PREFIX)/share/plasma-dynamic-island/scripts

SRC_PLASMOID      := dynamic-island
SRC_SCRIPTS       := scripts

.PHONY: help install install-plasmoid install-scripts uninstall print-paths plasma

help:
	@echo "Plasma Dynamic Island"
	@echo ""
	@echo "Targets:"
	@echo "  make install           Install plasmoid + scripts"
	@echo "  make install-plasmoid  Install applet only"
	@echo "  make install-scripts   Install scripts only"
	@echo "  make uninstall         Remove installed plasmoid + scripts"
	@echo "  make plasma            Restart plasmashell (plasmashell --replace)"
	@echo "  make print-paths       Show resolved install paths"
	@echo ""
	@echo "Configurable variables (override on the command line):"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  PLASMOID_DIR=$(PLASMOID_DIR)"
	@echo "  PLUGIN_ID=$(PLUGIN_ID)"
	@echo "  INSTALL_DIR=$(INSTALL_DIR)"
	@echo "  SCRIPTS_INSTALL_DIR=$(SCRIPTS_INSTALL_DIR)"

print-paths:
	@echo "INSTALL_DIR=$(INSTALL_DIR)"
	@echo "SCRIPTS_INSTALL_DIR=$(SCRIPTS_INSTALL_DIR)"

install: install-plasmoid install-scripts

install-plasmoid:
	@test -f "$(SRC_PLASMOID)/metadata.json" || { echo "Missing $(SRC_PLASMOID)/metadata.json"; exit 1; }
	@test -f "$(SRC_PLASMOID)/contents/ui/main.qml" || { echo "Missing $(SRC_PLASMOID)/contents/ui/main.qml"; exit 1; }
	mkdir -p "$(INSTALL_DIR)"
	cp -a "$(SRC_PLASMOID)/." "$(INSTALL_DIR)/"
	@echo "Installed plasmoid → $(INSTALL_DIR)"

install-scripts:
	@test -d "$(SRC_SCRIPTS)" || { echo "Missing $(SRC_SCRIPTS)/"; exit 1; }
	mkdir -p "$(SCRIPTS_INSTALL_DIR)"
	cp -a "$(SRC_SCRIPTS)/." "$(SCRIPTS_INSTALL_DIR)/"
	find "$(SCRIPTS_INSTALL_DIR)" -type f -name '*.sh' -exec chmod +x {} \;
	@echo "Installed scripts  → $(SCRIPTS_INSTALL_DIR)"

uninstall:
	rm -rf "$(INSTALL_DIR)"
	rm -rf "$(SCRIPTS_INSTALL_DIR)"
	@echo "Removed $(INSTALL_DIR)"
	@echo "Removed $(SCRIPTS_INSTALL_DIR)"

plasma:
	@echo "Restarting plasmashell in background..."
	@plasmashell --replace >/dev/null 2>&1 & echo "plasmashell --replace started (pid $$!)"
