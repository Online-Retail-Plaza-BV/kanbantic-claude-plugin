#!/usr/bin/env bash
# Kanbantic Claude Plugin — auto-updater
# Runs on session start, checks if a newer version is available on origin/main.

# Resolve repo root: hooks/ → plugin/ → repo root
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Skip if not a git repo (e.g. installed without git clone)
if [ ! -d "$REPO_ROOT/.git" ]; then
  exit 0
fi

cd "$REPO_ROOT" || exit 0

# Fetch silently (timeout after 5 seconds to avoid blocking)
git fetch --quiet origin main 2>/dev/null &
FETCH_PID=$!

# Wait max 5 seconds for fetch
( sleep 5 && kill $FETCH_PID 2>/dev/null ) &
TIMEOUT_PID=$!
wait $FETCH_PID 2>/dev/null
kill $TIMEOUT_PID 2>/dev/null

LOCAL=$(git rev-parse HEAD 2>/dev/null)
REMOTE=$(git rev-parse origin/main 2>/dev/null)

if [ -z "$LOCAL" ] || [ -z "$REMOTE" ]; then
  exit 0
fi

if [ "$LOCAL" != "$REMOTE" ]; then
  LOCAL_VERSION=$(grep '"version"' plugin/.claude-plugin/plugin.json 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
  REMOTE_VERSION=$(git show origin/main:plugin/.claude-plugin/plugin.json 2>/dev/null | grep '"version"' | head -1 | sed 's/.*: *"\(.*\)".*/\1/')

  if [ -n "$LOCAL_VERSION" ] && [ -n "$REMOTE_VERSION" ] && [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Kanbantic Plugin updating: v${LOCAL_VERSION} -> v${REMOTE_VERSION}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if git pull --ff-only origin main 2>/dev/null; then
      echo "  Plugin updated to v${REMOTE_VERSION}"
    else
      echo "  Auto-update failed. Run manually:"
      echo "     cd ~/.claude/plugins/local/kanbantic-claude-plugin && git pull"
    fi
    echo ""
  fi
fi
