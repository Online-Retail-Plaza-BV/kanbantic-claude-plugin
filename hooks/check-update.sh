#!/usr/bin/env bash
# Kanbantic Claude Plugin — update checker
# Runs on session start, checks if a newer version is available on origin/main.

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Skip if not a git repo (e.g. installed without git clone)
if [ ! -d "$PLUGIN_DIR/.git" ]; then
  exit 0
fi

cd "$PLUGIN_DIR" || exit 0

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
  LOCAL_VERSION=$(grep '"version"' .claude-plugin/plugin.json 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
  REMOTE_VERSION=$(git show origin/main:.claude-plugin/plugin.json 2>/dev/null | grep '"version"' | head -1 | sed 's/.*: *"\(.*\)".*/\1/')

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🔄 Kanbantic Plugin update available!"
  if [ -n "$LOCAL_VERSION" ] && [ -n "$REMOTE_VERSION" ] && [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
    echo "     Installed: v${LOCAL_VERSION} → Available: v${REMOTE_VERSION}"
  fi
  echo ""
  echo "  Run: cd ~/.claude/plugins/local/kanbantic-claude-plugin && git pull"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi
