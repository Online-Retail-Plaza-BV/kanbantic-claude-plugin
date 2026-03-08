# Kanbantic Claude Plugin

Claude Code plugin for Kanbantic goal lifecycle management. All artifacts are created and managed through Kanbantic MCP tools — no local file output.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| `kanbantic-goal-design` | `/design-goal` | Design a new goal or feature with specifications and test cases |
| `kanbantic-bug-report` | `/report-bug` | Quick bug intake: what's broken, steps to reproduce, severity |
| `kanbantic-goal-planning` | `/plan-goal` | Create implementation plan with phases, tasks, and code instructions |
| `kanbantic-goal-executing` | `/execute-goal` | Execute implementation plan phase by phase with reviews |
| `kanbantic-code-review` | *(auto)* | Review completed phase against specifications and test cases |
| `kanbantic-debugging` | *(manual)* | Systematic bug investigation with root cause analysis |

## Workflow

```
/design-goal → /plan-goal → /execute-goal
                                   ↓
                          code-review (per phase)

/report-bug → /plan-goal or debugging
```

1. **Design** — Collaborate on requirements → Creates Goal + Specs + Test Cases in Kanbantic
2. **Report Bug** — Quick intake → Creates Bug goal with steps to reproduce
3. **Plan** — Explore codebase → Creates Implementation Plan + Phases + Tasks + Code Instructions
4. **Execute** — Implement phase by phase → Updates task status, commits code, requests review
5. **Review** — Subagent reviews against specs → Approves or rejects phase with feedback

## Requirements

- [Claude Code](https://claude.ai/code) installed
- A Kanbantic API key (format: `ka_{agent-name}_{random}`) — request one from your workspace admin

## Setup (before installing)

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

> **Important**: Do NOT use `/mcp` to connect to Kanbantic. The plugin bundles the MCP server configuration; a manual `/mcp` connection creates a duplicate that causes errors.

## Installation

Install via the Claude Code plugin marketplace:

```bash
claude plugin install kanbantic-claude-plugin@kanbantic
```

Or use the reinstall script for a clean install:

```powershell
.\reinstall-kanbantic-plugin.ps1
```

## Principle

**Read from Kanbantic → Do the work → Write to Kanbantic**

All artifacts (goals, specifications, test cases, implementation plans, discussion entries) live in Kanbantic, not in local files. A developer with only Kanbantic access has everything needed to understand and implement any goal.

## Coexistence with Superpowers

This plugin replaces superpowers for Kanbantic-specific workflows:
- `brainstorming` → `kanbantic-goal-design`
- `writing-plans` → `kanbantic-goal-planning`
- `executing-plans` → `kanbantic-goal-executing`
- `requesting-code-review` → `kanbantic-code-review`
- `systematic-debugging` → `kanbantic-debugging`

Generic superpowers skills (TDD, verification, git worktrees) remain available if superpowers is also installed.

## License

MIT
