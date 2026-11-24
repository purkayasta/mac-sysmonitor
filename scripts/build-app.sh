#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/mac-sysmonitor.app"
MODULE_CACHE="$PROJECT_DIR/.build/ModuleCache"
mkdir -p "$DIST_DIR" "$MODULE_CACHE"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.mac-sysmonitor.XXXXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/mac-sysmonitor.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

# Compile directly: this dependency-free starter does not need package resolution.
swiftc -O -swift-version 6 \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$MODULE_CACHE" \
    Sources/MacSysMonitor/*.swift -o "$STAGED_APP/Contents/MacOS/mac-sysmonitor"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGED_APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signing is free and intended for local development only.
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
swift -module-cache-path "$MODULE_CACHE" scripts/install-built-app.swift "$STAGED_APP" "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
