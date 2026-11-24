#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$PROJECT_DIR/.build/AppIcon.iconset"
mkdir -p "$ICONSET" "$PROJECT_DIR/.build/ModuleCache"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$PROJECT_DIR/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$PROJECT_DIR/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
if ! iconutil -c icns "$ICONSET" -o "$PROJECT_DIR/Resources/AppIcon.icns"; then
    # Some Command Line Tools installations reject otherwise valid iconsets.
    # Package the already resized PNGs as standard ICNS chunks without re-encoding.
    swift -module-cache-path "$PROJECT_DIR/.build/ModuleCache" \
        "$PROJECT_DIR/scripts/package-icon.swift" "$ICONSET" "$PROJECT_DIR/Resources/AppIcon.icns"
fi
