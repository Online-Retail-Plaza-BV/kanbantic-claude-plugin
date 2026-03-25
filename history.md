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
- Step 11d (NEW): Writes MCP config to project-root `.mcp.json` for all projects with plugin enabled:
  ```json
  { "mcpServers": { "kanbantic": { "type": "http", "url": "https://kanbantic.com/mcp", "headers": { "Authorization": "Bearer ${KANBANTIC_API_KEY}" } } } }
  ```
  **Note:** Initially wrote to `.claude/mcp.json` — later discovered this is the wrong location. See "2026-03-09: MCP config in wrong location" entry below.
- Step 11e (NEW): Removes `.mcp.json` from plugin cache (safety net for old plugin versions)
- Step 12d (CHANGED): Validates project-root `.mcp.json` instead of plugin `.mcp.json`
- Step 12f (CHANGED): Excludes expected project-root `.mcp.json` files from conflict detection

**3. Kanbantic repo** (`.mcp.json` at project root):
- Created project-root `.mcp.json` with kanbantic MCP server config

### Why project-root `.mcp.json` works but plugin `.mcp.json` doesn't
- Project-root `.mcp.json` is loaded early in Claude Code's config chain and headers are attached to all HTTP requests from the start
- Plugin `.mcp.json` may be processed differently — the HTTP transport client may attempt discovery before applying plugin-provided headers
- The `${KANBANTIC_API_KEY}` env var expansion works identically in both locations
- The `mcpServers` wrapped format (project) vs flat format (plugin) may also affect header handling
- **Important:** The correct location is `.mcp.json` at the project root, NOT `.claude/mcp.json`. See "2026-03-09: MCP config in wrong location" entry below.

## 2026-03-09: MCP tools not found on fresh laptop after plugin install

### Symptom
After running `reinstall-kanbantic-plugin.ps1` on a new laptop, Claude Code shows the plugin as enabled but the MCP server does not appear in the "Manage MCP servers" list. Claude Code says: *"Ik kan geen Kanbantic MCP-tools vinden om direct goals op te vragen."*

Plugin status: `kanbantic-claude-plugin Plugin · kanbantic · √ enabled`
MCP servers: only shows `kie-ai`, `claude.ai Gmail`, `claude.ai Google Calendar` — no kanbantic.

### Diagnosis
1. Plugin is installed and enabled correctly in global settings ✓
2. `KANBANTIC_API_KEY` is set as persistent User variable ✓
3. Reinstall script completed "All checks passed!" ✓
4. BUT: the script only wrote MCP config to known projects (e.g., `D:\github\WpManagementStudio`)
5. The user ran Claude Code from `D:\GitHub\kanbantic-client` — a **different project**
6. `kanbantic-client` had no `.mcp.json` at its project root
7. MCP servers configured in `.mcp.json` are **project-scoped** — they only appear when Claude Code runs in that project directory

### Root Cause
**Reinstall script only writes MCP config to projects it already knows about.**

Step 11d of the script iterates `$projectSettingsPost`, which is built by scanning known code directories (`C:\github`, `D:\github`, etc.) for existing `.claude/settings.json` files. A fresh project that has never had the plugin enabled doesn't have `.claude/settings.json`, so the script skips it entirely.

Flow:
1. Script scans for `.claude/settings.json` files in known code directories
2. Finds `WpManagementStudio` (has existing settings) → writes MCP config ✓
3. `kanbantic-client` has no `.claude/` directory → not found → skipped ✗
4. User opens Claude Code in `kanbantic-client` → no `.mcp.json` at project root → no MCP server

### Fix
Updated `reinstall-kanbantic-plugin.ps1` step 11c to also include the **current working directory** (`$PWD`) as a target project. After building `$projectSettingsPost` from known directories, the script now:

1. Checks if `$PWD` is a git repo (has `.git` directory)
2. If `.claude/` directory doesn't exist → creates it
3. If `.claude/settings.json` doesn't exist → creates it with `enabledPlugins` containing the kanbantic plugin
4. Adds the path to `$projectSettingsPost` so step 11d automatically writes the MCP config

```powershell
# Also include the current working directory if it's a git repo (handles new/fresh projects)
$cwdClaudeDir = Join-Path $PWD '.claude'
$cwdSettingsFile = Join-Path $cwdClaudeDir 'settings.json'
if ((Test-Path (Join-Path $PWD '.git')) -and ($projectSettingsPost -notcontains $cwdSettingsFile)) {
    if (-not (Test-Path $cwdClaudeDir)) {
        New-Item -ItemType Directory -Path $cwdClaudeDir -Force | Out-Null
    }
    if (-not (Test-Path $cwdSettingsFile)) {
        $newSettings = [ordered]@{ enabledPlugins = [ordered]@{ $pluginId = $true } }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($cwdSettingsFile, ($newSettings | ConvertTo-Json -Depth 10), $utf8NoBom)
    }
    $projectSettingsPost += $cwdSettingsFile
}
```

**Expected output on fresh project after fix:**
```
> Add kanbantic to project-level enabledPlugins
  [OK] Created .claude/settings.json in current project (kanbantic-client)

> Write MCP server config to project root .mcp.json
  [OK] Created .mcp.json in kanbantic-client -> D:\github\kanbantic-client\.mcp.json

> Post-install validation
  [OK] MCP server config in .mcp.json (kanbantic-client)
```

### Lesson learned
The reinstall script must always include the **current working directory** as a target, regardless of whether it was previously known. Users typically `cd` into a project directory before running the script, so `$PWD` is the most important target.

## 2026-03-09: Claude Desktop app cannot connect to MCP server

### Symptom
When using the Claude Desktop app (Windows) and asking about Kanbantic goals, Claude responds: *"De pagina https://kanbantic.com/mcp geeft een fout — hij bestaat niet of is nog niet live."*

### Diagnosis
1. The MCP server at `https://kanbantic.com/mcp` uses **Streamable HTTP** transport (`MapMcp("/mcp")` in `src/Kanbantic.Mcp/Program.cs` line 155)
2. Streamable HTTP only accepts **POST** requests with JSON-RPC payloads
3. A GET request to `/mcp` returns 404/405 — the endpoint does not serve web pages
4. Claude Desktop (the AI in the desktop app) is trying to fetch the URL as a webpage, not connecting via MCP protocol
5. The MCP server is NOT configured in Claude Desktop — only the Claude Code plugin was installed

### Root Cause
**Claude Desktop app requires separate MCP server configuration** in `%APPDATA%\Claude\claude_desktop_config.json`. The plugin installation only configures Claude Code (CLI), not Claude Desktop.

When no MCP server is configured, Claude (the AI) interprets the URL as a webpage and tries to fetch it with a GET request, which fails because the server only handles POST.

### Fix
Create or edit `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "kanbantic": {
      "type": "http",
      "url": "https://kanbantic.com/mcp",
      "headers": {
        "Authorization": "Bearer ka_your-agent_your-key"
      }
    }
  }
}
```

**Important caveats:**
- Claude Desktop may not support `${ENV_VAR}` expansion — use the literal API key value
- Claude Desktop's HTTP MCP client may have the same probe-without-headers behavior as plugin-bundled configs (see 2026-03-09 entry above). If so, Claude Desktop would also fail to authenticate.
- After saving, restart Claude Desktop for changes to take effect
- **Not yet verified** — as of 2026-03-09, Claude Desktop compatibility with the Kanbantic MCP server has not been confirmed

### Architecture reference

```
┌─────────────────────────────────────────────────────────────────────┐
│ MCP Server: https://kanbantic.com/mcp                               │
│ Transport: Streamable HTTP (POST only, JSON-RPC)                    │
│ Auth: Bearer token (pre-shared API key, format: ka_name_random)     │
│ Backend: .NET ModelContextProtocol SDK, MapMcp("/mcp")              │
│ No OAuth/OIDC endpoints (all disabled to prevent Claude Code        │
│ from entering OAuth mode instead of using static Bearer tokens)     │
└─────────────────────────────────────────────────────────────────────┘
         ▲                              ▲
         │                              │
    Works ✓                      Not yet verified
         │                              │
┌────────┴─────────┐          ┌────────┴──────────┐
│ Claude Code CLI  │          │ Claude Desktop App│
│                  │          │                    │
│ Config location: │          │ Config location:   │
│ .mcp.json        │          │ %APPDATA%\Claude\  │
│ (project root)   │          │ claude_desktop_    │
│                  │          │ config.json        │
│ Env var: ✓       │          │                    │
│ ${VAR} expansion │          │ Env var: ✗ (maybe) │
│                  │          │ Use literal key    │
│ Created by:      │          │                    │
│ reinstall script │          │ Created by:        │
│ (step 11d)       │          │ manual only        │
└──────────────────┘          └────────────────────┘
```

## Reference: Complete MCP configuration chain

### Where MCP servers can be configured (in priority order)

| Location | Format | Scope | Headers sent? | Env var expansion? |
|----------|--------|-------|---------------|--------------------|
| `.mcp.json` (project root) | `{ "mcpServers": { ... } }` | Per project | ✓ Always | ✓ `${VAR}` |
| `~/.claude/settings.json` mcpServers | `{ "mcpServers": { ... } }` | Global | ✓ Always | ✓ `${VAR}` |
| `.claude/mcp.json` (WRONG) | `{ "mcpServers": { ... } }` | NOT read | ✗ N/A | N/A |
| Plugin `.mcp.json` (bundled) | `{ "name": { ... } }` (flat) | Per plugin | ✗ Unreliable | ✓ `${VAR}` |
| `~/.claude.json` (legacy) | `{ "mcpServers": { ... } }` | Global | ✓ | ✓ `${VAR}` |
| `%APPDATA%\Claude\claude_desktop_config.json` | `{ "mcpServers": { ... } }` | Desktop app | ? Unknown | ? Unknown |

**Rule: Always use project-root `.mcp.json` for Kanbantic.** NOT `.claude/mcp.json` (wrong location). Plugin-bundled configs do not reliably send Bearer tokens. Use `claude mcp add --scope project` to verify the correct location.

### Reinstall script step reference

| Step | What it does | Key files |
|------|-------------|-----------|
| 1 | Pre-flight: validate `KANBANTIC_API_KEY` | Windows User env var |
| 2-5 | Cleanup: remove all plugin/marketplace traces | `~/.claude/plugins/` |
| 6 | Cleanup: remove `enabledPlugins` entries | `.claude/settings.json` in all projects |
| 7 | Cleanup: remove OAuth credentials | `~/.claude/.credentials.json` |
| 8 | Cleanup: remove MCP server configs | `~/.claude/projects/*/settings.json`, global settings |
| 9 | Cleanup: remove repo-level `.mcp.json` and stale `.claude/mcp.json` | All git repos in known dirs |
| 10 | Cleanup: remove backup files | `~/.claude/backups/` |
| 11a | Install: add marketplace | `git@github.com:Online-Retail-Plaza-BV/kanbantic-claude-plugin.git` |
| 11b | Install: install plugin | `kanbantic-claude-plugin@kanbantic` |
| 11c | Config: add to `enabledPlugins` + include current directory | `.claude/settings.json` per project |
| 11d | Config: write MCP server config | `.mcp.json` at project root |
| 11e | Cleanup: remove plugin-bundled `.mcp.json` | Plugin cache |
| 12a-g | Validation: 7 checks | Plugin cache, registry, settings, MCP config, OAuth, conflicts, API key |

## 2026-03-10: Re-added `.mcp.json` to plugin (v1.7.0)

### Context
Comparison of the working Playwright plugin with the non-working Kanbantic plugin revealed the key structural difference: Playwright bundles a `.mcp.json` in its plugin directory that auto-configures the MCP server on install. The Kanbantic plugin (since v1.6.0) relied solely on the reinstall script to write project-root `.mcp.json` files, making installation fragile and multi-step.

### Changes (v1.7.0)
1. **Added `plugin/.mcp.json`** — bundles MCP server config directly in the plugin:
   ```json
   {
     "kanbantic": {
       "type": "http",
       "url": "https://kanbantic.com/mcp",
       "headers": {
         "Authorization": "Bearer ${KANBANTIC_API_KEY}"
       }
     }
   }
   ```
   This matches the Playwright plugin pattern: `{ "name": { "type": "...", ... } }` (flat format).

2. **Bumped version** to 1.7.0 in both `plugin/.claude-plugin/plugin.json` and `marketplace.json`.

### How it works
- Claude Code reads plugin-bundled `.mcp.json` and registers the MCP server automatically on install
- `${KANBANTIC_API_KEY}` is expanded from environment variables at runtime
- The `headers` field attaches `Authorization: Bearer <key>` to all HTTP requests
- User only needs to set `KANBANTIC_API_KEY` env var before installing the plugin

### Comparison with Playwright plugin

| Aspect | Playwright | Kanbantic (v1.7.0) |
|--------|-----------|-------------------|
| `.mcp.json` | `{"playwright": {"command": "npx", "args": [...]}}` | `{"kanbantic": {"type": "http", "url": "...", "headers": {...}}}` |
| Transport | stdio (local process) | HTTP (remote server) |
| Auth | None needed | Bearer token from `${KANBANTIC_API_KEY}` |
| User setup | None | Set `KANBANTIC_API_KEY` env var |

### Known caveat
Previous v1.5.0 testing (see entries above) found that plugin-bundled `.mcp.json` with HTTP transport did not reliably send Bearer headers — Claude Code's HTTP client would probe without headers first, get 401, and enter OAuth flow. This was **before** all OAuth discovery endpoints were removed from the server (v1.6.0 fix). With OAuth endpoints now returning 404, the client should fall back to using the configured headers. If issues persist, the reinstall script still writes project-root `.mcp.json` as a backup path.

### Troubleshooting checklist

When MCP tools are not found after installation, check in this order:

1. **`KANBANTIC_API_KEY`** — set as Windows User env var, starts with `ka_`
2. **`.mcp.json`** — exists at the **project root** (NOT `.claude/mcp.json`) with `type: "http"`
3. **`.claude/settings.json`** — has `enabledPlugins` with `kanbantic-claude-plugin@kanbantic: true`
4. **No stale OAuth** — `~/.claude/.credentials.json` has no kanbantic entries in `mcpOAuth`
5. **No duplicate configs** — no global `mcpServers` with kanbantic
6. **No plugin `.mcp.json`** — `~/.claude/plugins/cache/kanbantic/` should NOT contain `.mcp.json`
7. **No stale `.claude/mcp.json`** — project `.claude/mcp.json` should NOT have kanbantic entries (wrong location)
8. **Server reachable** — `curl -X POST https://kanbantic.com/mcp -H "Authorization: Bearer $KEY"` returns 200
9. **Restart Claude Code** — MCP config changes require a restart to take effect

## 2026-03-09: MCP config in wrong location — .mcp.json must be at project root

### Symptom
After running `reinstall-kanbantic-plugin.ps1` on a fresh project, the script reports success and creates `.claude/mcp.json` with the correct config. BUT `claude mcp list` shows no kanbantic server, and MCP tools are not available.

### Diagnosis
1. Script output shows: `[OK] Created mcp.json in test -> C:\github\test\.claude\mcp.json`
2. The file exists with correct content (type: http, Bearer token, URL)
3. Claude Code's `/mcp` command shows NO kanbantic server
4. Running `claude mcp add kanbantic --transport http --url https://kanbantic.com/mcp --header "Authorization: Bearer ${KANBANTIC_API_KEY}" --scope project` **does** work
5. After `claude mcp add`, the file `.mcp.json` appears at the **project root** (not in `.claude/`)
6. `claude mcp list` now shows: `kanbantic: https://kanbantic.com/mcp (HTTP) - ✓ Connected`

### Root Cause
**Claude Code reads project-scoped MCP server configs from `.mcp.json` at the project root, NOT from `.claude/mcp.json`.**

The reinstall script was writing to `.claude/mcp.json` (inside the `.claude/` directory). This is the wrong location. Claude Code's `claude mcp add --scope project` creates `.mcp.json` at the project root — that's the authoritative location.

Both files use the same JSON format:
```json
{ "mcpServers": { "kanbantic": { "type": "http", "url": "...", "headers": { ... } } } }
```

But only the project-root `.mcp.json` is read by Claude Code.

### Fix
Updated `reinstall-kanbantic-plugin.ps1`:

**Step 11d** — changed target from `.claude/mcp.json` to project-root `.mcp.json`:
```powershell
# Before (WRONG):
$mcpFile = Join-Path $claudeDir 'mcp.json'     # .claude/mcp.json

# After (CORRECT):
$claudeDir = Split-Path $settingsFile           # .claude/
$projectRoot = Split-Path $claudeDir            # project root
$mcpFile = Join-Path $projectRoot '.mcp.json'   # project/.mcp.json
```

**Step 9b** — updated comment to clarify `.claude/mcp.json` is now a stale/cleanup location

**Step 12d** — validation already correct (was already checking project-root `.mcp.json`)

**Step 12f** — fixed false positives: build exclusion list of expected project-root `.mcp.json` files so validation doesn't flag our own created files as "conflicting"

### Three PowerShell gotchas also fixed in this session

1. **`Select-Object -Unique` returns string, not array, for single result** — `$array += $string` does string concatenation instead of array append. Fix: wrap with `@()`:
   ```powershell
   $projectSettingsPost = @($projectSettingsPost | Where-Object ... | Select-Object -Unique)
   ```

2. **`Get-ChildItem -Recurse` without `-Depth` scans into `node_modules`** — causes script to hang for minutes scanning 100K+ files. Fix: add `-Depth 3` (or `-Depth 4` for `.claude/mcp.json` pattern):
   ```powershell
   Get-ChildItem -Path $codeDir -Filter 'settings.json' -Recurse -Depth 3
   ```

3. **`.git` directory check too restrictive for `$PWD`** — fresh projects or non-git-repo projects were skipped. Fix: removed `.git` requirement for the current working directory inclusion.

### Verified
Tested end-to-end in clean `C:\github\test\` directory:
```
> Write MCP server config to project root .mcp.json
  [OK] Created .mcp.json in test -> C:\github\test\.mcp.json

> Post-install validation
  [OK] MCP server config in .mcp.json (test)
  [OK] No conflicting MCP server configs
```

`claude mcp list` output: `kanbantic: https://kanbantic.com/mcp (HTTP) - ✓ Connected`

## 2026-03-25: Plugin stops working — stale OAuth credential with `plugin:` prefix escapes cleanup

### Symptom
After running the install script (`irm https://kanbantic.com/install.ps1 | iex`), the plugin still cannot connect to the MCP server. Claude Code shows the plugin as enabled, but MCP tools are unavailable. The `/plugin` command reconnects but the MCP server fails authentication.

### Diagnosis
1. Plugin installed and enabled in global settings ✓
2. `KANBANTIC_API_KEY` env var set correctly ✓
3. Project-root `.mcp.json` has correct `mcpServers` config with Bearer token ✓
4. Plugin-bundled `.mcp.json` already removed from cache (step 6d working) ✓
5. BUT: `~/.claude/.credentials.json` contains a stale `mcpOAuth` entry:
   ```json
   "mcpOAuth": {
       "plugin:kanbantic-claude-plugin:kanbantic|dc64643e74db3403": {
           "serverName": "plugin:kanbantic-claude-plugin:kanbantic",
           "serverUrl": "https://kanbantic.com/mcp",
           "accessToken": "",
           "expiresAt": 0,
           "discoveryState": {
               "authorizationServerUrl": "https://kanbantic.com/"
           }
       }
   }
   ```
6. The install script's cleanup (step 5f) uses wildcard `$_.Name -like 'kanbantic*'`
7. The actual key is `plugin:kanbantic-claude-plugin:kanbantic|dc64643e74db3403` — starts with `plugin:`, not `kanbantic`
8. **The wildcard does NOT match** → the stale OAuth entry survives cleanup

### Root Cause
**Install script's OAuth cleanup wildcard `'kanbantic*'` misses keys with `plugin:` prefix.**

Claude Code stores plugin MCP OAuth credentials with the key pattern `plugin:<plugin-name>:<server-name>|<hash>`. The cleanup in step 5f filtered on `'kanbantic*'` (starts with `kanbantic`), but the actual key starts with `plugin:`. The same bug existed in validation step 7e.

**Effect chain:**
1. Claude Code finds the stale `mcpOAuth` entry for `plugin:kanbantic-claude-plugin:kanbantic`
2. Entry has `accessToken: ""` and `expiresAt: 0` → expired/empty
3. Claude Code attempts to refresh via OAuth discovery at `https://kanbantic.com/`
4. Server has no OAuth endpoints (removed in March 2026) → discovery fails
5. Plugin MCP server is marked as "not authenticated"
6. Even though the project-root `.mcp.json` has valid Bearer token config, the stale OAuth credential takes precedence for the plugin-registered MCP server

### Fix
**1. install.ps1 step 5f** (cleanup) — changed wildcard from `'kanbantic*'` to `'*kanbantic*'`:
```powershell
# Before (MISSES plugin-prefixed keys):
$props = @($j.mcpOAuth.PSObject.Properties | Where-Object { $_.Name -like 'kanbantic*' })

# After (matches all kanbantic-related OAuth entries):
$props = @($j.mcpOAuth.PSObject.Properties | Where-Object { $_.Name -like '*kanbantic*' })
```

**2. install.ps1 step 7e** (validation) — same wildcard fix:
```powershell
# Before:
$oauthProps = @($creds.mcpOAuth.PSObject.Properties | Where-Object { $_.Name -like 'kanbantic*' })

# After:
$oauthProps = @($creds.mcpOAuth.PSObject.Properties | Where-Object { $_.Name -like '*kanbantic*' })
```

**3. Direct fix** — removed the entire `mcpOAuth` section from `~/.claude/.credentials.json`

### Lesson learned
Claude Code uses different key naming patterns for MCP OAuth credentials depending on how the MCP server was registered:
- **Project-root `.mcp.json`**: key starts with the server name (e.g., `kanbantic|<hash>`)
- **Plugin-bundled `.mcp.json`**: key starts with `plugin:<plugin-name>:<server-name>|<hash>`

Any wildcard matching on MCP credential keys must use `*kanbantic*` (both-sided wildcard) to catch all variants, not `kanbantic*` (prefix-only).

### Updated troubleshooting checklist
Added to the existing checklist (item 4):
> 4. **No stale OAuth** — `~/.claude/.credentials.json` has no kanbantic entries in `mcpOAuth`. Check for BOTH `kanbantic*` AND `plugin:*kanbantic*` key patterns.
