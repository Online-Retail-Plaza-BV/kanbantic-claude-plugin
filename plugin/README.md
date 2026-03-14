# Kanbantic Claude Plugin

Claude Code plugin for Kanbantic issue lifecycle management. All artifacts are created and managed through Kanbantic MCP tools — no local file output.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| `kanbantic-issue-design` | `/design-issue` | Design a new issue or feature with specifications and test cases |
| `kanbantic-bug-report` | `/report-bug` | Quick bug intake: what's broken, steps to reproduce, severity |
| `kanbantic-issue-planning` | `/plan-issue` | Create implementation plan with phases, tasks, and code instructions |
| `kanbantic-issue-executing` | `/execute-issue` | Execute implementation plan phase by phase with reviews |
| `kanbantic-code-review` | *(auto)* | Review completed phase against specifications and test cases |
| `kanbantic-debugging` | *(manual)* | Systematic bug investigation with root cause analysis |

## Workflow

```
/design-issue → /plan-issue → /execute-issue
                                   ↓
                          code-review (per phase)

/report-bug → /plan-issue or debugging
```

1. **Design** — Collaborate on requirements → Creates Issue + Specs + Test Cases in Kanbantic
2. **Report Bug** — Quick intake → Creates Bug issue with steps to reproduce
3. **Plan** — Explore codebase → Creates Implementation Plan + Phases + Tasks + Code Instructions
4. **Execute** — Implement phase by phase → Updates task status, commits code, requests review
5. **Review** — Subagent reviews against specs → Approves or rejects phase with feedback

## Requirements

- [Claude Code](https://claude.ai/code) installed
- A Kanbantic API key (format: `ka_{agent-name}_{random}`) — request one from your workspace admin

## Setup (before installing)

### 1. Set your API key

The plugin authenticates via the `KANBANTIC_API_KEY` environment variable. Set it **once** as a persistent Windows User Environment Variable:

1. Open **Control Panel → System → Advanced system settings → Environment Variables**
2. Under **User variables**, click **New**
3. Variable name: `KANBANTIC_API_KEY`
4. Variable value: your API key (e.g. `ka_dev-yourname_abc123...`)
5. Click **OK** and **restart your terminal**

Verify:
```powershell
echo $env:KANBANTIC_API_KEY
# should print your key
```

### 2. Configure the MCP server

The MCP server connection must be configured in your project's `.claude/mcp.json` file. Add this configuration:

```json
{
  "mcpServers": {
    "kanbantic": {
      "type": "http",
      "url": "https://kanbantic.com/mcp",
      "headers": {
        "Authorization": "Bearer ${KANBANTIC_API_KEY}"
      }
    }
  }
}
```

> **Note**: The MCP config is placed in `.claude/mcp.json` (not bundled in the plugin) because Claude Code's HTTP transport requires project-level configuration for reliable environment variable expansion and header injection. The reinstall script handles this automatically.

> **Important**: Do NOT use `/mcp` to manually connect to Kanbantic. The project-level config handles it.

## Installation

**Recommended**: Use the reinstall script for a clean install (handles everything automatically):

```powershell
.\reinstall-kanbantic-plugin.ps1
```

Or install manually via the Claude Code plugin marketplace:

```bash
claude plugin install kanbantic-claude-plugin@kanbantic
# Then add the MCP config above to your project's .claude/mcp.json
```

## Principle

**Read from Kanbantic → Do the work → Write to Kanbantic**

All artifacts (issues, specifications, test cases, implementation plans, discussion entries) live in Kanbantic, not in local files. A developer with only Kanbantic access has everything needed to understand and implement any issue.

## Coexistence with Superpowers

This plugin replaces superpowers for Kanbantic-specific workflows:
- `brainstorming` → `kanbantic-issue-design`
- `writing-plans` → `kanbantic-issue-planning`
- `executing-plans` → `kanbantic-issue-executing`
- `requesting-code-review` → `kanbantic-code-review`
- `systematic-debugging` → `kanbantic-debugging`

Generic superpowers skills (TDD, verification, git worktrees) remain available if superpowers is also installed.

## License

MIT
