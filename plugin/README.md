# Kanbantic Claude Plugin

Claude Code plugin for Kanbantic goal lifecycle management. All artifacts are created and managed through Kanbantic MCP tools — no local file output.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| `kanbantic-goal-design` | `/design-goal` | Design a new goal, feature, or bug with specifications and test cases |
| `kanbantic-goal-planning` | `/plan-goal` | Create implementation plan with phases, tasks, and code instructions |
| `kanbantic-goal-executing` | `/execute-goal` | Execute implementation plan phase by phase with reviews |
| `kanbantic-code-review` | *(auto)* | Review completed phase against specifications and test cases |
| `kanbantic-debugging` | *(manual)* | Systematic bug investigation with root cause analysis |

## Workflow

```
/design-goal → /plan-goal → /execute-goal
                                   ↓
                          code-review (per phase)
```

1. **Design** — Collaborate on requirements → Creates Goal + Specs + Test Cases in Kanbantic
2. **Plan** — Explore codebase → Creates Implementation Plan + Phases + Tasks + Code Instructions
3. **Execute** — Implement phase by phase → Updates task status, commits code, requests review
4. **Review** — Subagent reviews against specs → Approves or rejects phase with feedback

## Requirements

- [Claude Code](https://claude.ai/code) installed
- A Kanbantic API key (format: `ka_{agent-name}_{random}`)

## Installation

Install via the Claude Code plugin marketplace:

```bash
claude plugin install kanbantic-claude-plugin@kanbantic
```

Or clone to local plugins directory:

```bash
git clone https://github.com/Online-Retail-Plaza-BV/kanbantic-claude-plugin.git ~/.claude/plugins/local/kanbantic-claude-plugin
```

## Setup

The plugin bundles the Kanbantic MCP server configuration automatically — no separate `.mcp.json` needed.

Set your API key as an environment variable:

```bash
# Linux / macOS
export KANBANTIC_API_KEY="ka_your-agent_your-key"

# Windows (PowerShell)
$env:KANBANTIC_API_KEY = "ka_your-agent_your-key"

# Windows (CMD)
set KANBANTIC_API_KEY=ka_your-agent_your-key
```

To make it persistent, add the export to your shell profile (`~/.bashrc`, `~/.zshrc`, or Windows System Environment Variables).

Request an API key from your Kanbantic workspace administrator.

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
