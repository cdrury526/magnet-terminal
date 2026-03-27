# Magnet Terminal — Build & Distribution
#
# Targets:
#   make build     — Release build (unsigned, for local dev)
#   make dmg       — Create DMG installer from release build
#   make sign      — Code sign + notarize the DMG for distribution
#   make release   — Full pipeline: build → dmg → sign
#   make clean     — Remove build artifacts
#
# Environment variables for signing (set in your shell or CI):
#   CODESIGN_IDENTITY  — Developer ID Application certificate name
#                        e.g., "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID           — Apple ID email for notarization
#   APPLE_TEAM_ID      — Apple Developer Team ID
#   APPLE_PASSWORD     — App-specific password (or @keychain:notarytool)

SHELL := /bin/bash
.DEFAULT_GOAL := build

# App metadata (extracted from pubspec.yaml and xcconfig)
APP_NAME := Magnet Terminal
BUNDLE_ID := com.magnet.terminal
VERSION := $(shell grep '^version:' pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
BUILD_NUMBER := $(shell grep '^version:' pubspec.yaml | sed 's/.*+//')

# Paths
BUILD_DIR := build/macos/Build/Products/Release
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
DMG_DIR := build/dmg
DMG_NAME := MagnetTerminal-$(VERSION).dmg
DMG_PATH := $(DMG_DIR)/$(DMG_NAME)

# Signing defaults (override via environment)
CODESIGN_IDENTITY ?=
APPLE_ID ?=
APPLE_TEAM_ID ?=
APPLE_PASSWORD ?=

# ==============================================================================
# Build targets
# ==============================================================================

.PHONY: build dmg sign release clean help

## build: Flutter release build (unsigned, for local development)
build:
	@echo "==> Building Magnet Terminal v$(VERSION)+$(BUILD_NUMBER) (release)..."
	flutter build macos --release
	@echo "==> Build complete: $(APP_BUNDLE)"

## dmg: Create a DMG installer from the release build
dmg: build
	@echo "==> Creating DMG..."
	@mkdir -p $(DMG_DIR)
	@rm -f $(DMG_PATH)
	@# Create a temporary directory for DMG contents
	@mkdir -p $(DMG_DIR)/staging
	@cp -R "$(APP_BUNDLE)" "$(DMG_DIR)/staging/"
	@ln -sf /Applications "$(DMG_DIR)/staging/Applications"
	@# Create the DMG
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder "$(DMG_DIR)/staging" \
		-ov -format UDZO \
		"$(DMG_PATH)"
	@rm -rf "$(DMG_DIR)/staging"
	@echo "==> DMG created: $(DMG_PATH)"

## sign: Code sign the app bundle and notarize the DMG
##       Requires CODESIGN_IDENTITY, APPLE_ID, APPLE_TEAM_ID, APPLE_PASSWORD
sign:
	@if [ -z "$(CODESIGN_IDENTITY)" ]; then \
		echo "ERROR: CODESIGN_IDENTITY is not set."; \
		echo "  Set it to your Developer ID Application certificate name, e.g.:"; \
		echo '  export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"'; \
		exit 1; \
	fi
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(APPLE_TEAM_ID)" ] || [ -z "$(APPLE_PASSWORD)" ]; then \
		echo "ERROR: Notarization credentials not set."; \
		echo "  Required: APPLE_ID, APPLE_TEAM_ID, APPLE_PASSWORD"; \
		exit 1; \
	fi
	@echo "==> Signing app bundle with: $(CODESIGN_IDENTITY)"
	@# Sign all nested frameworks and dylibs first (deep sign)
	@find "$(APP_BUNDLE)" -name "*.framework" -o -name "*.dylib" | while read f; do \
		codesign --force --options runtime --timestamp \
			--sign "$(CODESIGN_IDENTITY)" \
			--entitlements macos/Runner/Release.entitlements \
			"$$f"; \
	done
	@# Sign the main app bundle
	codesign --force --deep --options runtime --timestamp \
		--sign "$(CODESIGN_IDENTITY)" \
		--entitlements macos/Runner/Release.entitlements \
		"$(APP_BUNDLE)"
	@echo "==> Verifying signature..."
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"
	@echo "==> Signing DMG..."
	codesign --force --timestamp \
		--sign "$(CODESIGN_IDENTITY)" \
		"$(DMG_PATH)"
	@echo "==> Submitting for notarization..."
	xcrun notarytool submit "$(DMG_PATH)" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--password "$(APPLE_PASSWORD)" \
		--wait
	@echo "==> Stapling notarization ticket..."
	xcrun stapler staple "$(DMG_PATH)"
	@echo "==> Done! Signed and notarized: $(DMG_PATH)"

## release: Full pipeline — build, package DMG, sign, and notarize
release: build dmg sign
	@echo "==> Release complete: $(DMG_PATH)"
	@echo "    Version: $(VERSION)+$(BUILD_NUMBER)"
	@echo "    Bundle:  $(BUNDLE_ID)"

## clean: Remove all build artifacts
clean:
	@echo "==> Cleaning build artifacts..."
	flutter clean
	@rm -rf $(DMG_DIR)
	@echo "==> Clean complete"

## help: Show this help message
help:
	@echo "Magnet Terminal — Build & Distribution"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build    Release build (unsigned, for local development)"
	@echo "  dmg      Create DMG installer (runs build first)"
	@echo "  sign     Code sign + notarize (requires signing env vars)"
	@echo "  release  Full pipeline: build → dmg → sign + notarize"
	@echo "  clean    Remove build artifacts"
	@echo ""
	@echo "Signing environment variables:"
	@echo "  CODESIGN_IDENTITY  Developer ID Application certificate name"
	@echo "  APPLE_ID           Apple ID email for notarization"
	@echo "  APPLE_TEAM_ID      Apple Developer Team ID"
	@echo "  APPLE_PASSWORD     App-specific password for notarytool"
	@echo ""
	@echo "Example:"
	@echo '  export CODESIGN_IDENTITY="Developer ID Application: Chris Drury (ABCDEF1234)"'
	@echo '  export APPLE_ID="chris@example.com"'
	@echo '  export APPLE_TEAM_ID="ABCDEF1234"'
	@echo '  export APPLE_PASSWORD="@keychain:notarytool"'
	@echo "  make release"
