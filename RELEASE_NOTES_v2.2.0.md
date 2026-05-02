# Plugin v2.2.0 — Prepared status

## What changed

Adds the new `Prepared` lane-status (Kanbantic backend KBT-F235) as a first-class transition in the workflow:

```
New → Triaged → Prepared → InProgress → Review → Done
              ↑________↑              (Cancelled is terminal from any non-Done status)
              prepare  execute (claim_issue)
```

### Skill updates

- **`kanbantic-issue-prepare`** now transitions the issue to `Prepared` (via `update_issue_status`) once all readiness-checks are green — Step 6a. The issue surfaces in the new Prepared kanban-column awaiting claim. If readiness is still failing, the issue stays on `Triaged` (no transition) and Step 6b reports what's missing — re-run the skill once the artifacts are added.

- **`kanbantic-issue-execute`** Step 1 gate-check now accepts both `Prepared` (preferred) and `Triaged` + `isReadyToClaim` (legacy, for issues that pre-date the data-migration). Step 2 HARD-GATE updated: `claim_issue` atomically promotes `New`/`Triaged`/`Prepared` → `InProgress` in a single MCP call (KBT-RL052). The pre-state behavior table now lists Prepared rows for both fresh-claim and same-principal-resume scenarios.

- **`kanbantic-issue-triage`** handoff message now mentions that prepare transitions the issue to `Prepared` (i.p.v. only flipping a `isReadyToClaim` flag), so users / agents know to look for the Prepared kanban-column rather than filtering Triaged-with-flag.

### MCP tool descriptions (Kanbantic.Mcp)

- `update_issue_status`, `list_issues`, `claim_issue`, `bootstrap_agent` now mention `Prepared` and the new lane-flow.

## Backwards-compat

- **No breaking changes** for plugins, MCP consumers, or DB-stored data:
  - `IssueStatus` enum value `Prepared = 6` (append, not insert; pre-F2 numeric values unchanged) — KBT-BD075.
  - `IsReadyToClaim` is now derived from `Status == Prepared` (KBT-SR266) — single source of truth. Read-side consumers see the same boolean field.
  - Backend data-migration (KBT-SR267) promotes existing `Triaged`-issues that meet the Prepared readiness-criteria on first deploy of the matching API version.
  - Execute skill keeps accepting `Triaged` as bron-status for issues that haven't migrated yet, so older agents and pre-migration runs keep working.

## Migration guide for agents

If your custom workflow relied on `update_issue_status` going straight from `Triaged → InProgress`, switch to `claim_issue` (which now atomically does both, single call). For prepare-skill users: nothing changes — the skill handles the new transition for you.

## Cross-links

- KBT-F235 — backend Feature
- KBT-SR265 / KBT-RL051 / KBT-RL052 / KBT-SR266 / KBT-SR267 / KBT-BD075 — backing specs
- KBT-US521 — user story
