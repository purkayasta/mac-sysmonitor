#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/dist/SysMon.app"
BUNDLE_ID="dev.local.mac-sysmonitor"
PURGE=false
DRY_RUN=false

usage() {
    cat <<'HELP'
Usage: bash scripts/uninstall.sh [--app PATH] [--purge] [--dry-run]

Move dist/SysMon.app to Trash by default.
  --app PATH   Move a specific copy to Trash, e.g. /Applications/SysMon.app.
  --purge      Delete this user's saved preferences after a successful move.
  --dry-run    Show the actions without changing anything.
  --help       Show this help.

All running SysMon instances will close; unresponsive instances will be force-closed.
Unsaved settings in those instances may be discarded. Source files and build caches are kept.
HELP
}

fail() { printf '%s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            [ "$#" -ge 2 ] && [ -n "$2" ] || fail '--app requires a path.'
            APP_PATH="$2"
            shift 2
            ;;
        --purge) PURGE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1 (use --help)." ;;
    esac
done

# Resolve the parent only; never follow a symlink masquerading as the app bundle.
while [ "${APP_PATH%/}" != "$APP_PATH" ]; do APP_PATH="${APP_PATH%/}"; done
APP_NAME="$(basename "$APP_PATH")"
case "$APP_NAME" in
    SysMon.app) ;;
    *) fail 'Expected a path named SysMon.app.' ;;
esac
[ ! -L "$APP_PATH" ] || fail 'Refusing to remove a symlink; provide the actual app path.'

if [ -e "$APP_PATH" ]; then
    [ -d "$APP_PATH" ] || fail 'The app path is not a directory.'
    APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd -P)/$APP_NAME"
    PLIST="$APP_PATH/Contents/Info.plist"
    ACTUAL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null)" || fail 'Cannot read the app bundle identifier.'
    [ "$ACTUAL_ID" = "$BUNDLE_ID" ] || fail "Refusing to remove a different app: $ACTUAL_ID"
    if "$DRY_RUN"; then
        printf 'Would close all running SysMon instances, force-closing any that remain.\n'
        printf 'Would move to Trash: %s\n' "$APP_PATH"
    else
        HELPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sysmon-uninstall.XXXXXXXX")"
        trap 'rm -rf -- "$HELPER_DIR"' EXIT
        # Reuse the build cache; a fresh cache recompiles Apple's Swift modules.
        MODULE_CACHE="$PROJECT_DIR/.build/ModuleCache"
        mkdir -p "$MODULE_CACHE"
        progress() { printf '\r[%-20s] %3d%% %s\n' "$1" "$2" "$3"; }
        progress '██░░░░░░░░░░░░░░░░░░' 10 'Preparing uninstaller'
        swiftc -swift-version 6 -module-cache-path "$MODULE_CACHE" \
            "$PROJECT_DIR/Sources/SysMon/AppRemoval.swift" \
            "$PROJECT_DIR/Sources/SysMon/AppInstanceShutdown.swift" \
            "$PROJECT_DIR/scripts/stop-running-apps.swift" -o "$HELPER_DIR/stop-running-apps"
        progress '████████░░░░░░░░░░░░' 40 'Closing SysMon instances'
        "$HELPER_DIR/stop-running-apps" "$APP_PATH" ||
            fail 'Could not complete uninstall. Saved settings were kept.'
        progress '████████████████████' 100 'Complete'
        printf 'Moved to Trash: %s\n' "$APP_PATH"
    fi
else
    printf 'App already absent: %s\n' "$APP_PATH"
    exit 0
fi

if "$PURGE"; then
    if "$DRY_RUN"; then
        printf 'Would delete preferences: %s (current user)\n' "$BUNDLE_ID"
    else
        "$HELPER_DIR/stop-running-apps" || fail 'Could not stop all SysMon instances. Saved settings were kept.'
        if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
            defaults delete "$BUNDLE_ID"
            printf 'Deleted preferences: %s\n' "$BUNDLE_ID"
        else
            printf 'No saved preferences found: %s\n' "$BUNDLE_ID"
        fi
    fi
else
    printf 'Saved settings kept. Use --purge to remove them.\n'
fi
