INSTALL_DIR ?= $(HOME)/Applications
APP         := ClaudeBar.app
# Keychain access is tied to the code signature; "-" (ad-hoc) changes on every build.
# Use a stable identity: make install SIGN_ID="Apple Development: Name (TEAMID)"
SIGN_ID     ?= ClaudeBar Dev
CERT_NAME   ?= ClaudeBar Dev
SOURCES     := $(wildcard Sources/ClaudeBar/*.swift)
KEYCHAIN    := security delete-generic-password -s com.claudebar.oauth

.DEFAULT_GOAL := all
.PHONY: all build install open uninstall cert clean show-history

## build: compile ClaudeBar.app in this directory
build: $(APP)

$(APP): $(SOURCES) Makefile
	@mkdir -p .build
	swiftc -O -parse-as-library -target "$$(uname -m)-apple-macos13.0" $(SOURCES) -o .build/ClaudeBar
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS"
	@cp .build/ClaudeBar "$(APP)/Contents/MacOS/ClaudeBar"
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '<key>CFBundleExecutable</key><string>ClaudeBar</string>' \
	  '<key>CFBundleIdentifier</key><string>com.claudebar.app</string>' \
	  '<key>CFBundleName</key><string>ClaudeBar</string>' \
	  '<key>CFBundleDisplayName</key><string>ClaudeBar</string>' \
	  '<key>CFBundlePackageType</key><string>APPL</string>' \
	  '<key>CFBundleShortVersionString</key><string>1.0.0</string>' \
	  '<key>CFBundleVersion</key><string>1</string>' \
	  '<key>LSMinimumSystemVersion</key><string>13.0</string>' \
	  '<key>LSUIElement</key><true/>' \
	  '<key>NSHumanReadableCopyright</key><string>MIT License</string>' \
	  '</dict></plist>' > "$(APP)/Contents/Info.plist"
	@codesign --force --sign "$(SIGN_ID)" "$(APP)"
	@echo "Built $(APP) — run: open $(APP)"

## cert: create a self-signed code-signing certificate in the login keychain (one time)
cert:
	@security find-identity -p codesigning | grep -q "$(CERT_NAME)" && { echo "$(CERT_NAME) already exists"; exit 0; }; \
	d=$$(mktemp -d) && \
	printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=$(CERT_NAME)\n[ext]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > $$d/c.cnf && \
	openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config $$d/c.cnf -keyout $$d/k.pem -out $$d/c.pem 2>/dev/null && \
	openssl pkcs12 -export -legacy -inkey $$d/k.pem -in $$d/c.pem -passout pass:x -out $$d/c.p12 2>/dev/null || openssl pkcs12 -export -inkey $$d/k.pem -in $$d/c.pem -passout pass:x -out $$d/c.p12; \
	security import $$d/c.p12 -P x -T /usr/bin/codesign -k ~/Library/Keychains/login.keychain-db && \
	echo "Created '$(CERT_NAME)'. Now run: make install SIGN_ID=\"$(CERT_NAME)\""; rm -rf $$d

## clean: remove build outputs
clean:
	@rm -rf "$(APP)" .build
	@echo "Cleaned."

## show-history: print the recorded usage history (change points per account/window)
show-history:
	@python3 -c 'import json,os,datetime as d; p=os.path.expanduser("~/Library/Application Support/ClaudeBar/history.json"); \
	h=json.load(open(p)) if os.path.exists(p) else {}; \
	print("No history yet.") if not h else None; \
	[print(k+"\n"+"\n".join("  %s  %.2f%%"%(d.datetime.fromtimestamp(s["t"]).strftime("%Y-%m-%d %H:%M:%S"),s["v"]) for s in v)) for k,v in sorted(h.items())]'

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
