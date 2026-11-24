#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH=/Applications/SysMon.app
case "$#" in
    0) ;;
    1)
        if [ "$1" = --help ] || [ "$1" = -h ]; then
            printf 'Usage: bash scripts/update-app.sh [--app APP_PATH]\n'
            exit 0
        fi
        printf 'Usage: bash scripts/update-app.sh [--app APP_PATH]\n' >&2
        exit 1
        ;;
    2)
        if [ "$1" != --app ] || [ -z "$2" ]; then
            printf 'Usage: bash scripts/update-app.sh [--app APP_PATH]\n' >&2
            exit 1
        fi
        APP_PATH="$2"
        ;;
    *)
        printf 'Usage: bash scripts/update-app.sh [--app APP_PATH]\n' >&2
        exit 1
        ;;
esac
exec bash "$PROJECT_DIR/scripts/build-app.sh" --update "$APP_PATH"
