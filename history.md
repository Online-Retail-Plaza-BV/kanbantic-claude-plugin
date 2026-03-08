# Kanbantic Claude Plugin - Troubleshooting History

## 2026-03-08: MCP Server "Auth: not authenticated" after plugin install

### Symptom
After installing the plugin, the MCP server shows:
- Status: connected
- Auth: not authenticated
- Capabilities: none

### Diagnosis
1. The `KANBANTIC_API_KEY` env var IS set correctly (`ka_dev-kanbantic-se_...`)
2. The API key IS valid - direct `curl` with Bearer token to `https://kanbantic.com/mcp` returns 200 with capabilities
3. Without auth header, server correctly returns 401
4. The server does NOT have an SSE endpoint (`/mcp/sse` returns 404) - it uses **Streamable HTTP** (JSON-RPC over POST to `/mcp`)
5. The `.mcp.json` had `"type": "sse"` which is the **wrong transport type** for this server, and SSE is deprecated in Claude Code

### Root Cause
**Wrong transport type in `.mcp.json`**: `"type": "sse"` should be `"type": "http"`.

The SSE transport tries to establish an SSE connection which doesn't exist on this server. The HTTP transport sends JSON-RPC POST requests with headers (including the Bearer token), matching the server's actual transport.

### Fix
Changed `.mcp.json` from:
```json
{ "type": "sse", "url": "https://kanbantic.com/mcp", ... }
```
to:
```json
{ "type": "http", "url": "https://kanbantic.com/mcp", ... }
```

Updated in:
- `plugin/.mcp.json` (source)
- `~/.claude/plugins/cache/kanbantic/kanbantic-claude-plugin/1.5.0/.mcp.json` (cached)
