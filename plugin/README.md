# Kanbantic Claude Plugin

Claude plugin for Kanbantic issue lifecycle management. All artifacts are created and managed through Kanbantic MCP tools — no local file output.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| `kanbantic-issue-design` | `/design-issue` | Design a new issue or feature with specifications and test cases |
| `kanbantic-bug-report` | `/report-bug` | Quick bug intake: what's broken, steps to reproduce, severity |
| `kanbantic-issue-planning` | `/plan-issue` | Create implementation plan with phases, tasks, and code instructions |
| `kanbantic-issue-execute` | `/execute-issue` | Execute an issue: claim, implement tasks, push, transition to Review |
| `kanbantic-issue-review` | *(auto)* | Review + merge + close + knowledge-extractie — completes Review → Done |
| `kanbantic-debugging` | *(manual)* | Systematic bug investigation with root cause analysis |

## Workflow

```
/design-issue → /plan-issue → /execute-issue
                                   ↓
                          issue-review (per phase, + merge + close on final approve)

/report-bug → /plan-issue or debugging
```

1. **Design** — Collaborate on requirements → Creates Issue + Specs + Test Cases in Kanbantic
2. **Report Bug** — Quick intake → Creates Bug issue with steps to reproduce
3. **Plan** — Explore codebase → Creates Implementation Plan + Phases + Tasks + Code Instructions
4. **Execute** — Implement phase by phase → Updates task status, commits code, requests review
5. **Review** — Subagent reviews against specs → Approves or rejects phase with feedback

## Architecture

Since **v1.11.0**, the plugin connects to the Kanbantic MCP server through a local **stdio proxy** (`proxy/kanbantic-mcp-proxy.js`) instead of Claude's built‑in HTTP MCP transport.

```
Claude (Code or Desktop) ──stdio──► kanbantic-mcp-proxy.js ──HTTP+Bearer──► https://kanbantic.com/mcp
```

Why stdio and not HTTP:

- Claude's HTTP MCP client is **OAuth‑first**. One 401 response poisons `~/.claude/.credentials.json` with a cached `discoveryState`, and from that moment on the statically configured `Authorization: Bearer …` header is silently ignored — forever, or until the credentials file is cleaned.
- stdio transport has no OAuth flow, no discovery, and no credentials cache. The proxy handles HTTP + Bearer auth itself, and Claude never sees a 401.
- Zero npm dependencies (Node.js built‑ins only).

**Do not use** `"type": "http"` MCP configs for Kanbantic. They will break within hours or days.

## Requirements

- [Claude Code](https://claude.ai/code) **or** Claude Desktop (Windows App)
- [Node.js](https://nodejs.org) — the stdio proxy runs as `node …`
- A Kanbantic API key (format: `ka_{agent-name}_{random}`) — request one from your workspace admin

## Setup — shared step: set the API key

The proxy authenticates with `KANBANTIC_API_KEY`. On Windows, set it **once** as a persistent User Environment Variable:

1. Open **Control Panel → System → Advanced system settings → Environment Variables**
2. Under **User variables**, click **New**
3. Variable name: `KANBANTIC_API_KEY`
4. Variable value: your API key (e.g. `ka_dev-yourname_abc123...`)
5. Click **OK**
6. **Sign out of Windows and sign back in** (or reboot)

> **Why sign out / in is required:** Windows GUI apps (Claude Desktop, Cowork) inherit their environment from `explorer.exe`, which is started at sign‑in. When you edit a User Environment Variable, Windows broadcasts a `WM_SETTINGCHANGE` message — new PowerShell and cmd sessions pick it up, but most GUI apps (including Claude Desktop) do not. Until you sign out and back in, those apps still see the old environment.

Verify in a **new** terminal:

```powershell
echo $env:KANBANTIC_API_KEY
# should print your key
```

## Setup — Claude Code

Claude Code is supported out of the box. The bundled `plugin/.mcp.json` registers the stdio proxy automatically when the plugin is enabled:

```jsonc
{
  "kanbantic": {
    "command": "node",
    "args": ["${CLAUDE_PLUGIN_ROOT}/proxy/kanbantic-mcp-proxy.js"],
    "env": { "KANBANTIC_API_KEY": "${KANBANTIC_API_KEY}" }
  }
}
```

Claude Code expands both `${CLAUDE_PLUGIN_ROOT}` and `${KANBANTIC_API_KEY}` correctly. Nothing else is required.

**Installation** — run the hosted installer (one‑liner, no clone required):

```powershell
irm https://kanbantic.com/install.ps1 | iex
```

Or via the marketplace directly:

```bash
claude plugin install kanbantic-claude-plugin@kanbantic
```

> **Important:** Do **not** add a `.mcp.json` at the project root or in `.claude/mcp.json` with a Kanbantic entry. The plugin‑bundled config is authoritative. A duplicate HTTP entry will re‑introduce OAuth cache poisoning.

## Setup — Claude Desktop (Windows App)

Claude Desktop does not honor Claude Code's plugin system, so it cannot use the bundled `plugin/.mcp.json` and the `${CLAUDE_PLUGIN_ROOT}` placeholder. You must register an stdio bridge manually in `%APPDATA%\Claude\claude_desktop_config.json`.

> **Do not** use "Add Custom Connector" in the Desktop UI. That flow routes through claude.ai's OAuth broker, which requires OAuth 2.1 / DCR discovery endpoints — these are intentionally absent on the Kanbantic MCP server (see Architecture). You will get "Couldn't reach the MCP server", and each attempt can leave stale entries in `%APPDATA%\Claude\.credentials.json` that later interfere with the stdio routes below.

**Recommended approach: bundled proxy with the `KANBANTIC_API_KEY` User env var.** Since v1.14.0 the proxy reads the key from `HKCU\Environment` as a fallback, so Desktop no longer needs to inherit the env var from `explorer.exe` and you do **not** need to embed the key literally in the config.

### 1. Set the User environment variable

Follow the "Setup — shared step: set the API key" section above. A full sign‑out is **no longer required** for Desktop — the proxy reads directly from the registry if the variable isn't in the inherited environment.

### 2. Edit `claude_desktop_config.json`

Open (or create) `%APPDATA%\Claude\claude_desktop_config.json` and add:

```json
{
  "mcpServers": {
    "kanbantic": {
      "command": "node",
      "args": [
        "C:\\Users\\<YourUsername>\\.claude\\plugins\\cache\\kanbantic\\kanbantic-claude-plugin\\<version>\\proxy\\kanbantic-mcp-proxy.js"
      ]
    }
  }
}
```

Notes:

- The server **name** must be `kanbantic` (not `framework` or anything else). The plugin skills reference tools as `mcp__kanbantic__*`; any other name causes "tool not found" errors.
- Replace `<YourUsername>` with your Windows user name and `<version>` with the currently installed plugin version (e.g. `1.14.0`). You'll need to update `<version>` whenever the plugin updates — or switch to the `mcp-remote` alternative below if you'd rather not.
- No `env` block is needed: the proxy picks up `KANBANTIC_API_KEY` from the inherited environment, and falls back to `HKCU\Environment` on Windows.
- Do **not** add a `"type": "http"` entry for Kanbantic. It hits the OAuth cache poisoning bug described in the Architecture section.

### 3. Restart Claude Desktop

Close the app completely (including the system tray icon) and relaunch.

### 4. Verify

Ask Claude Desktop: *"List my Kanbantic issues."* You should see tools named `mcp__kanbantic__list_issues`, `mcp__kanbantic__get_issue`, etc. being invoked. If you see a 401 or "KANBANTIC_API_KEY not found", re‑check that the User env var is set correctly: `reg query HKCU\Environment /v KANBANTIC_API_KEY` in a PowerShell window must return your key.

### Alternative: `mcp-remote` with literal API key

If you'd rather avoid the hardcoded plugin-cache path (which changes with each plugin update), point Claude Desktop at `mcp-remote` instead:

```json
{
  "mcpServers": {
    "kanbantic": {
      "command": "cmd",
      "args": [
        "/c",
        "npx",
        "-y",
        "mcp-remote@latest",
        "https://kanbantic.com/mcp",
        "--header",
        "Authorization: Bearer ka_your-agent_your-key"
      ]
    }
  }
}
```

Caveats: the API key is embedded **literally** in the config (treat the file as a secret — don't commit or share it), and `cmd /c` is required on Windows so `npx.cmd` resolves correctly.

## Troubleshooting

When the MCP server doesn't respond, check in this order:

1. **Server name is `kanbantic`** (Desktop) — in `claude_desktop_config.json` the `mcpServers` key must be exactly `kanbantic`. Other names (e.g. `framework`) register tools under the wrong prefix and every skill fails with "tool not found".
2. **API key resolution** — the proxy reads `KANBANTIC_API_KEY` from (a) `process.env`, (b) `HKCU\Environment` on Windows as fallback. Verify with `reg query HKCU\Environment /v KANBANTIC_API_KEY` — the value must start with `ka_`. If you're using the `mcp-remote` alternative, the key must instead appear literally in the `--header` argument and no `${...}` placeholders are allowed.
3. **Claude Code env var flow** — Code expands `${KANBANTIC_API_KEY}` from the inherited environment. Verify in a **new** PowerShell window: `echo $env:KANBANTIC_API_KEY`.
4. **Sign‑out/sign‑in is no longer required for Desktop** (v1.14.0+). The proxy reads the registry directly, bypassing explorer.exe's env inheritance. For Claude Code, a new terminal window is still enough; GUI apps launched from an old explorer.exe session may still need sign‑out if they relied on `${KANBANTIC_API_KEY}` expansion at config time.
5. **Node.js is installed** — `node --version` returns a version. `npx` must be on PATH for the Desktop `mcp-remote` route.
6. **Plugin is enabled** (Claude Code) — `.claude/settings.json` has `enabledPlugins` with `kanbantic-claude-plugin@kanbantic: true`.
7. **No stale HTTP config** — no `.mcp.json` at any project root with a Kanbantic entry that uses `"type": "http"`. Remove any such entries.
8. **No stale OAuth** — inspect `~/.claude/.credentials.json` (Claude Code) and `%APPDATA%\Claude\.credentials.json` (Claude Desktop) and remove any `mcpOAuth` entries matching `*kanbantic*` or `plugin:*kanbantic*`.
9. **Server reachable** — `curl -X POST https://kanbantic.com/mcp -H "Authorization: Bearer <your-key>" -H "Accept: application/json, text/event-stream" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'` should return 200 with capabilities.
10. **Restart the host** — Claude Code: close and reopen. Claude Desktop: close (incl. system tray) and relaunch.

## Principle

**Read from Kanbantic → Do the work → Write to Kanbantic**

All artifacts (issues, specifications, test cases, implementation plans, discussion entries) live in Kanbantic, not in local files. A developer with only Kanbantic access has everything needed to understand and implement any issue.

## Coexistence with Superpowers

This plugin replaces superpowers for Kanbantic‑specific workflows:

- `brainstorming` → `kanbantic-issue-design`
- `writing-plans` → `kanbantic-issue-planning`
- `executing-plans` → `kanbantic-issue-execute`
- `requesting-code-review` → `kanbantic-issue-review`
- `systematic-debugging` → `kanbantic-debugging`

Generic superpowers skills (TDD, verification, git worktrees) remain available if superpowers is also installed.

## License

MIT
