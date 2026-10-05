IMAGE      ?= claudebar-builder
SIGN_DIR   := signing
KEYSTORE   := $(SIGN_DIR)/claudebar.jks
KS_PROPS   := $(SIGN_DIR)/keystore.properties
KEY_ALIAS  ?= claudebar
DIST       := dist
GRADLE_HOME_DIR := .gradle-docker
APP_ID     := com.example.claudebar

# Run containers as the host user so generated files aren't root-owned.
DOCKER_RUN = docker run --rm \
	--user $$(id -u):$$(id -g) \
	-v "$(CURDIR)":/project \
	-v "$(CURDIR)/$(GRADLE_HOME_DIR)":/gradle-cache \
	-w /project $(IMAGE)

GRADLE = $(DOCKER_RUN) gradle --no-daemon --console=plain

.PHONY: help image keystore debug release all install fingerprint verify wrapper shell clean distclean

help:
	@echo "make image        build the Docker build image"
	@echo "make keystore     create $(KEYSTORE) + $(KS_PROPS) if missing (never overwrites)"
	@echo "make debug        build $(DIST)/ClaudeBar-debug.apk   (signed with the shared key)"
	@echo "make release      build $(DIST)/ClaudeBar-release.apk (signed with the shared key)"
	@echo "make all          debug + release"
	@echo "make verify       verify APK signatures and show cert fingerprint"
	@echo "make install      adb install the debug APK (host adb)"
	@echo "make wrapper      generate gradle wrapper (for Android Studio / CLI users)"
	@echo "make shell        shell inside the build container"
	@echo "make clean        remove build outputs"

.image-stamp: Dockerfile
	docker build -t $(IMAGE) .
	@touch $@

image: .image-stamp

$(GRADLE_HOME_DIR):
	mkdir -p $@

# Creates the keystore only if it doesn't exist. Reuses the stored password if
# keystore.properties already exists; otherwise generates a random one.
$(KEYSTORE): .image-stamp
	@mkdir -p $(SIGN_DIR)
	@if [ -f "$(KEYSTORE)" ]; then exit 0; fi; \
	if [ -f "$(KS_PROPS)" ]; then \
		pw=$$(sed -n 's/^storePassword=//p' $(KS_PROPS)); \
	else \
		pw=$$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24); \
		printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
			"$(KEYSTORE)" "$$pw" "$(KEY_ALIAS)" "$$pw" > $(KS_PROPS); \
		chmod 600 $(KS_PROPS); \
	fi; \
	echo ">> Generating signing key $(KEYSTORE)"; \
	$(DOCKER_RUN) keytool -genkeypair -v \
		-keystore $(KEYSTORE) -storetype PKCS12 \
		-alias $(KEY_ALIAS) -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=ClaudeBar, O=ClaudeBar, C=US" \
		-storepass "$$pw" -keypass "$$pw"; \
	chmod 600 $(KEYSTORE); \
	echo ">> Back up $(SIGN_DIR)/ - losing it means you can't update installed builds."

keystore: $(KEYSTORE)

debug: $(KEYSTORE) | $(GRADLE_HOME_DIR)
	$(GRADLE) :app:assembleDebug
	@mkdir -p $(DIST)
	cp app/build/outputs/apk/debug/app-debug.apk $(DIST)/ClaudeBar-debug.apk
	@echo ">> $(DIST)/ClaudeBar-debug.apk"

release: $(KEYSTORE) | $(GRADLE_HOME_DIR)
	$(GRADLE) :app:assembleRelease
	@mkdir -p $(DIST)
	cp app/build/outputs/apk/release/app-release.apk $(DIST)/ClaudeBar-release.apk
	@echo ">> $(DIST)/ClaudeBar-release.apk"

all: debug release

verify:
	@for f in $(DIST)/ClaudeBar-debug.apk $(DIST)/ClaudeBar-release.apk; do \
		[ -f $$f ] || continue; echo "== $$f"; \
		$(DOCKER_RUN) apksigner verify --print-certs $$f | grep -E 'Signer #1 certificate (DN|SHA-256)'; \
	done

fingerprint: $(KEYSTORE)
	@pw=$$(sed -n 's/^storePassword=//p' $(KS_PROPS)); \
	$(DOCKER_RUN) keytool -list -v -keystore $(KEYSTORE) -storepass "$$pw" | grep -E 'SHA256|Alias'

install: debug
	adb install -r $(DIST)/ClaudeBar-debug.apk

wrapper: .image-stamp | $(GRADLE_HOME_DIR)
	$(GRADLE) wrapper --gradle-version 8.7

shell: .image-stamp | $(GRADLE_HOME_DIR)
	docker run --rm -it --user $$(id -u):$$(id -g) -v "$(CURDIR)":/project \
		-v "$(CURDIR)/$(GRADLE_HOME_DIR)":/gradle-cache -w /project $(IMAGE) bash

clean:
	rm -rf app/build build $(DIST)

# Keeps signing/ (your key!). Remove it by hand if you really mean to.
distclean: clean
	rm -rf .gradle $(GRADLE_HOME_DIR) .image-stamp
