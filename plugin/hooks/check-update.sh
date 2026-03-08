#!/usr/bin/env bash
# Kanbantic Claude Plugin — session-start checks
# 1. Verify KANBANTIC_API_KEY is set
# 2. Check for plugin updates

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── 1. API key check ───────────────────────────────────────────────────
# The plugin requires KANBANTIC_API_KEY as a Windows User Environment Variable.
if [ -z "$KANBANTIC_API_KEY" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  KANBANTIC_API_KEY is not set"
  echo ""
  echo "  Set it in Windows:"
  echo "    Control Panel > System > Advanced > Environment Variables"
  echo "    Add User variable: KANBANTIC_API_KEY = ka_..."
  echo ""
  echo "  Then restart your terminal and Claude Code."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi

# ── 2. Plugin update check ─────────────────────────────────────────────
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
