#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE=build
APP_DIR="$PROJECT_DIR/dist/SysMon.app"
if [ "$#" -gt 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != --update ] || [ -z "$2" ]; then
        printf 'Usage: bash scripts/build-app.sh [--update APP_PATH]\n' >&2
        exit 1
    fi
    MODE=update
    case "$2" in
        /*) APP_DIR="$2" ;;
        *) APP_DIR="$PWD/$2" ;;
    esac
fi
cd "$PROJECT_DIR"

MODULE_CACHE="$PROJECT_DIR/.build/ModuleCache"
DESTINATION_PARENT="$(dirname "$APP_DIR")"
if [ "$MODE" = build ]; then
    mkdir -p "$DESTINATION_PARENT"
fi
mkdir -p "$MODULE_CACHE"
STAGING_DIR="$(mktemp -d "$DESTINATION_PARENT/.SysMon.XXXXXXXX")"
trap 'if [ ! -e "$STAGING_DIR/.keep-for-recovery" ]; then rm -rf -- "$STAGING_DIR"; fi' EXIT
STAGED_APP="$STAGING_DIR/SysMon.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

# Compile directly: this dependency-free starter does not need package resolution.
printf 'Compiling SysMon…\n'
swiftc -O -swift-version 6 \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$MODULE_CACHE" \
    Sources/SysMon/*.swift -o "$STAGED_APP/Contents/MacOS/SysMon"
printf 'Packaging app resources…\n'
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGED_APP/Contents/Resources/AppIcon.icns"

printf 'Signing app…\n'
# Ad-hoc signing is free and intended for local development only.
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
printf 'Preparing installer…\n'
swiftc -swift-version 6 -module-cache-path "$MODULE_CACHE" \
    Sources/SysMon/AppRemoval.swift scripts/QuitRequest.swift scripts/install-built-app.swift -o "$STAGING_DIR/install-built-app"
printf 'Installing app…\n'
"$STAGING_DIR/install-built-app" "$MODE" "$STAGED_APP" "$APP_DIR"
if [ "$MODE" = update ]; then
    printf 'Updated %s\n' "$APP_DIR"
else
    printf 'Built %s\n' "$APP_DIR"
fi
