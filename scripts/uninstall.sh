#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/dist/mac-sysmonitor.app"
BUNDLE_ID="dev.local.mac-sysmonitor"
PURGE=false
DRY_RUN=false

usage() {
    cat <<'HELP'
Usage: bash scripts/uninstall.sh [--app PATH] [--purge] [--dry-run]

Move dist/mac-sysmonitor.app to Trash by default.
  --app PATH   Move a specific copy to Trash, e.g. /Applications/mac-sysmonitor.app.
  --purge      Delete this user's saved preferences after a successful move.
  --dry-run    Show the actions without changing anything.
  --help       Show this help.

Quit mac-sysmonitor before uninstalling. Source files and build caches are kept.
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
APP_PATH="${APP_PATH%/}"
[ "$(basename "$APP_PATH")" = 'mac-sysmonitor.app' ] || fail 'Expected a path named mac-sysmonitor.app.'
[ ! -L "$APP_PATH" ] || fail 'Refusing to remove a symlink; provide the actual app path.'

if [ -e "$APP_PATH" ]; then
    [ -d "$APP_PATH" ] || fail 'The app path is not a directory.'
    APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd -P)/mac-sysmonitor.app"
    PLIST="$APP_PATH/Contents/Info.plist"
    ACTUAL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null)" || fail 'Cannot read the app bundle identifier.'
    [ "$ACTUAL_ID" = "$BUNDLE_ID" ] || fail "Refusing to remove a different app: $ACTUAL_ID"
    if ! "$DRY_RUN" && pgrep -x mac-sysmonitor >/dev/null; then
        fail 'Quit mac-sysmonitor using SM → Quit mac-sysmonitor, then retry.'
    fi
    if "$DRY_RUN"; then
        printf 'Would move to Trash: %s\n' "$APP_PATH"
    else
        swift "$PROJECT_DIR/scripts/move-to-trash.swift" "$APP_PATH" ||
            fail 'Could not move the app to Trash. Saved settings were kept.'
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
        if pgrep -x mac-sysmonitor >/dev/null; then
            fail 'Quit mac-sysmonitor before deleting preferences.'
        fi
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
