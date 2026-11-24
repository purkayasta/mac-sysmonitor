#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Run from a normal Terminal with GitHub access, after `gh auth login`.
gh auth status >/dev/null
OWNER="$(gh api user --jq .login)"
REPOSITORY="$OWNER/mac-sysmonitor"
HTTPS_REMOTE="https://github.com/$REPOSITORY.git"
SSH_REMOTE="git@github.com:$REPOSITORY.git"

if [ ! -e .git ]; then
    git init -b main
fi
[ "$(git branch --show-current)" = main ] || {
    printf 'Expected branch main; refusing to change branches automatically.\n' >&2
    exit 1
}
git diff --cached --quiet || {
    printf 'Existing staged changes found. Commit or unstage them before running this script.\n' >&2
    exit 1
}

if git remote get-url origin >/dev/null 2>&1; then
    EXISTING_REMOTE="$(git remote get-url origin)"
    case "$EXISTING_REMOTE" in
        "$HTTPS_REMOTE"|"$SSH_REMOTE") ;;
        *) printf 'Origin points elsewhere; refusing to replace it.\n' >&2; exit 1 ;;
    esac
fi

# Explicit paths exclude generated bundles, compiler caches, and unrelated files.
git add -- .gitignore AGENTS.md Package.swift README.md Resources Sources Tests scripts
if ! git diff --cached --quiet; then
    git commit -m "Set up mac-sysmonitor and document installation"
fi

if ! VISIBILITY="$(gh repo view "$REPOSITORY" --json visibility --jq .visibility 2>/dev/null)"; then
    gh repo create "$REPOSITORY" --private \
        --description 'Native Swift menu bar system monitor for Apple Silicon macOS'
    VISIBILITY="$(gh repo view "$REPOSITORY" --json visibility --jq .visibility)"
fi
[ "$VISIBILITY" = PRIVATE ] || {
    printf 'Repository is not private; refusing to push.\n' >&2
    exit 1
}

if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$HTTPS_REMOTE"
fi
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -u origin main
gh repo view "$REPOSITORY" --json url,visibility
