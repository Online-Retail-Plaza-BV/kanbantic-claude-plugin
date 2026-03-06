#!/usr/bin/env bash
# Kanbantic Claude Plugin — auto-update checker
# Runs on session start, checks GitHub for a newer plugin version.

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE_URL="https://raw.githubusercontent.com/Online-Retail-Plaza-BV/kanbantic-claude-plugin/main/plugin/.claude-plugin/plugin.json"

# Read local version
LOCAL_VERSION=$(grep '"version"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
if [ -z "$LOCAL_VERSION" ]; then
  exit 0
fi

# Fetch remote version (timeout after 5 seconds)
REMOTE_VERSION=$(curl -sf --max-time 5 "$REMOTE_URL" 2>/dev/null | grep '"version"' | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
if [ -z "$REMOTE_VERSION" ]; then
  exit 0
fi

if [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Kanbantic Plugin update available: v${LOCAL_VERSION} -> v${REMOTE_VERSION}"
  echo ""
  echo "  Run: claude plugin install kanbantic-claude-plugin"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi
