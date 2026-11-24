#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Compile directly: this dependency-free starter does not need package resolution.
BIN_DIR="$PROJECT_DIR/.build/local-release"
mkdir -p "$BIN_DIR" "$PROJECT_DIR/.build/ModuleCache"
swiftc -O -swift-version 6 \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$PROJECT_DIR/.build/ModuleCache" \
    Sources/MacSysMonitor/*.swift -o "$BIN_DIR/mac-sysmonitor"
APP_DIR="$PROJECT_DIR/dist/mac-sysmonitor.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/mac-sysmonitor" "$APP_DIR/Contents/MacOS/mac-sysmonitor"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc signing is free and intended for local development only.
codesign --force --sign - "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
