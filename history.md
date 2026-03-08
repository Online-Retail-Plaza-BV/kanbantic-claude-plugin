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

**Note:** This fix alone was NOT sufficient — see next entry.

## 2026-03-09: MCP still "Auth: not authenticated" after transport fix

### Symptom
Same as above: Status: connected, Auth: not authenticated, Capabilities: none.
The transport type fix (sse → http) was correct but not the full root cause.

### Diagnosis
1. `curl` with Bearer token returns 200 with capabilities — server auth works
2. The 401 response has `WWW-Authenticate: Bearer` (no resource_metadata) — correct
3. BUT the server still exposed **OAuth discovery endpoints**:
   - `/mcp/.well-known/openid-configuration` → 200 with full OIDC config
   - `/.well-known/oauth-authorization-server` → 200 with OAuth metadata
   - `/mcp/register`, `/mcp/authorize`, `/mcp/token` — full OAuth flow
4. Claude Code discovers these endpoints and enters **OAuth mode**, which causes it to:
   - Ignore statically configured Bearer tokens from `.mcp.json` headers
   - Show "Auth: not authenticated" (meaning no OAuth session)
   - Show "Capabilities: none" (initialization never completes with token)

### Root Cause
**OAuth discovery endpoints active on the MCP server.** When Claude Code finds ANY OAuth/OIDC discovery endpoint, it enters OAuth mode and stops using static Bearer tokens from the `headers` config.

The previous fix already disabled `/.well-known/oauth-protected-resource` with the correct reasoning, but missed the other OAuth endpoints.

### Fix
Removed ALL OAuth discovery and flow endpoints from `src/Kanbantic.Mcp/Program.cs`:
- `/mcp/.well-known/openid-configuration`
- `/mcp/.well-known/oauth-authorization-server`
- `/.well-known/oauth-authorization-server`
- `/mcp/.well-known/jwks.json`
- `/mcp/register`
- `/mcp/authorize` (GET + POST)
- `/mcp/token`

Also removed the now-unused `GetBaseUrl()` helper and in-memory OAuth client store.

Deployed to production: commit `aa47911`.

**Note:** This fix alone was NOT sufficient — see next entry.

## 2026-03-09: MCP still "Auth: not authenticated" after OAuth removal

### Symptom
Same as before: Status: connected, Auth: not authenticated, Capabilities: none.
OAuth endpoints are confirmed gone (all return 404). Bearer token auth works perfectly via `curl`. The `KANBANTIC_API_KEY` env var is set and available to Node.js (`process.env`).

### Diagnosis
1. All OAuth discovery endpoints return 404 — confirmed removed
2. `curl -X POST https://kanbantic.com/mcp -H "Authorization: Bearer $KEY"` → 200 + capabilities ✓
3. `curl -X POST https://kanbantic.com/mcp` (no auth) → 401 + `WWW-Authenticate: Bearer` ✓
4. Plugin's `.mcp.json` uses flat format: `{ "kanbantic": { "type": "http", "headers": { "Authorization": "Bearer ${KANBANTIC_API_KEY}" } } }`
5. Env var IS available to Node.js and the Claude Code process
6. Project `.claude/mcp.json` has empty `{ "mcpServers": {} }` — no kanbantic entry
7. No conflicting MCP configs, no stale OAuth credentials

### Root Cause
**Plugin-bundled `.mcp.json` with HTTP transport does not reliably send configured headers.**

Claude Code's HTTP MCP client implementation appears to probe the server first **without** the configured headers (from `.mcp.json`). When the server returns `401 + WWW-Authenticate: Bearer`, the client enters the MCP spec's OAuth authorization flow:

1. Client sends `initialize` to `/mcp` **without** Authorization header
2. Server returns `401` with `WWW-Authenticate: Bearer`
3. Per MCP spec, client MUST follow the authorization flow: look for `resource_metadata` param → try `/.well-known/oauth-protected-resource` discovery
4. Discovery fails (all OAuth endpoints return 404)
5. Client marks server as "not authenticated" — never falls back to static Bearer token from `.mcp.json` `headers` config
6. Capabilities remain "none" because `initialize` was never successfully completed

The issue is specific to **plugin-bundled `.mcp.json`** with HTTP transport. Project-level `.claude/mcp.json` configs are the primary, well-tested path and DO send configured headers on all requests (including the initial `initialize`).

### Fix
Moved MCP server configuration from plugin `.mcp.json` (flat format) to project-level `.claude/mcp.json` (standard `mcpServers` format):

**1. Plugin changes** (`kanbantic-claude-plugin` v1.6.0):
- Removed `plugin/.mcp.json` (no longer bundled with plugin)
- Updated README: MCP config is now in project `.claude/mcp.json`, managed by reinstall script

**2. Reinstall script changes** (`reinstall-kanbantic-plugin.ps1`):
- Step 11d (NEW): Writes MCP config to project `.claude/mcp.json` for all projects with plugin enabled:
  ```json
  { "mcpServers": { "kanbantic": { "type": "http", "url": "https://kanbantic.com/mcp", "headers": { "Authorization": "Bearer ${KANBANTIC_API_KEY}" } } } }
  ```
- Step 11e (NEW): Removes `.mcp.json` from plugin cache (safety net for old plugin versions)
- Step 12d (CHANGED): Validates project `.claude/mcp.json` instead of plugin `.mcp.json`
- Step 12f (CHANGED): Only flags repo-level `.mcp.json` and global settings as conflicts (project `.claude/mcp.json` is now expected)

**3. Kanbantic repo** (`.claude/mcp.json`):
- Updated from empty `{ "mcpServers": {} }` to include kanbantic MCP server config

### Why project-level `.claude/mcp.json` works but plugin `.mcp.json` doesn't
- Project `.claude/mcp.json` is loaded early in Claude Code's config chain and headers are attached to all HTTP requests from the start
- Plugin `.mcp.json` may be processed differently — the HTTP transport client may attempt discovery before applying plugin-provided headers
- The `${KANBANTIC_API_KEY}` env var expansion works identically in both locations
- The `mcpServers` wrapped format (project) vs flat format (plugin) may also affect header handling
