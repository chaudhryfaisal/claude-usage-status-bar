INSTALL_DIR ?= /Applications
APP         := ClaudeBar.app
KEYCHAIN    := security delete-generic-password -s com.claudebar.oauth

.DEFAULT_GOAL := all
.PHONY: all build install open uninstall

## build: compile ClaudeBar.app in this directory
build:
	@./scripts/build-app.sh

## install: build and copy the app to INSTALL_DIR (may prompt for sudo)
install: build
	@osascript -e 'quit app "ClaudeBar"' >/dev/null 2>&1 || true
	@rm -rf "$(INSTALL_DIR)/$(APP)"
	@cp -R "$(APP)" "$(INSTALL_DIR)/" || { echo "Permission denied — retry with: sudo make install"; exit 1; }
	@echo "Installed $(INSTALL_DIR)/$(APP)"

## open: launch the installed app
open:
	@test -d "$(INSTALL_DIR)/$(APP)" || { echo "Not installed — run 'make install' first."; exit 1; }
	@open "$(INSTALL_DIR)/$(APP)"

## uninstall: quit and remove the app (leaves your Keychain token alone)
uninstall:
	@osascript -e 'quit app "ClaudeBar"' >/dev/null 2>&1 || true
	@rm -rf "$(INSTALL_DIR)/$(APP)" "$(APP)"
	@echo "Removed $(APP). OAuth token left behind — drop it with: $(KEYCHAIN)"

## all: build, install, open
all: build install open