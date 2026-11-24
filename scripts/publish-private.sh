#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

git rev-parse --verify --quiet 'refs/heads/main^{commit}' >/dev/null || {
    printf 'Commit the files you want to publish on main first.\n' >&2
    exit 1
}
[ "$(git branch --show-current)" = main ] || {
    printf 'Expected branch main; refusing to change branches automatically.\n' >&2
    exit 1
}
WORKTREE_STATUS="$(git status --porcelain)"
if [ -n "$WORKTREE_STATUS" ]; then
    printf 'Publishing committed changes only. Local edits and untracked files are excluded.\n' >&2
fi

# Run from a normal Terminal with GitHub access, after `gh auth login`.
gh auth status >/dev/null
OWNER="$(gh api user --jq .login)"
REPOSITORY="$OWNER/mac-sysmonitor"
HTTPS_REMOTE="https://github.com/$REPOSITORY.git"
SSH_REMOTE="git@github.com:$REPOSITORY.git"

if git remote get-url origin >/dev/null 2>&1; then
    EXISTING_REMOTE="$(git remote get-url origin)"
    case "$EXISTING_REMOTE" in
        "$HTTPS_REMOTE"|"$SSH_REMOTE") ;;
        *) printf 'Origin points elsewhere; refusing to replace it.\n' >&2; exit 1 ;;
    esac
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

# A push URL can override the fetch URL, and multiple push URLs send to every destination.
if ! git remote get-url --push --all origin | awk -v https="$HTTPS_REMOTE" -v ssh="$SSH_REMOTE" '
    NR == 1 { valid = ($0 == https || $0 == ssh) }
    END { exit !(NR == 1 && valid) }
'; then
    printf 'Expected exactly one origin push URL for %s; refusing to push.\n' "$REPOSITORY" >&2
    exit 1
fi
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
    push --no-follow-tags --recurse-submodules=no -u origin refs/heads/main:refs/heads/main
gh repo view "$REPOSITORY" --json url,visibility
