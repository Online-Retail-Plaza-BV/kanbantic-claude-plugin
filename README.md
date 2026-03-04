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
- Kanbantic MCP server configured in `.mcp.json`
- MCP API key (`ka_{agent-name}_{random}`)

## Installation

```bash
# Clone to local plugins directory
git clone https://github.com/<org>/kanbantic-claude-plugin.git ~/.claude/plugins/local/kanbantic-claude-plugin
```

## MCP Configuration

Ensure your project has a `.mcp.json` with the Kanbantic server:

```json
{
  "mcpServers": {
    "kanbantic": {
      "type": "sse",
      "url": "https://your-kanbantic-instance.com/mcp/sse",
      "headers": {
        "Authorization": "ApiKey ka_your-agent_your-key"
      }
    }
  }
}
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
