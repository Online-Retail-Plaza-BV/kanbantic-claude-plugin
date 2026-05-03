# Plugin v2.3.0 — InDeployment status

## What changed

Adds the new `InDeployment` lane-status (Kanbantic backend KBT-F236) as a first-class transition in the workflow:

```
New → Triaged → Prepared → InProgress → Review → InDeployment → Done
                                                ↑________________↑
                                                review-skill   manual / deploy webhooks
```

### Skill updates

- **`kanbantic-issue-review`** Step 8 now transitions the issue to `InDeployment` (via `update_issue_status`) after merge to main, instead of directly to `Done`. The Done-transition is a separate operational step that follows after staging+production deploy verification — Step 8 surfaces those instructions to the caller. Auto-transition `InDeployment → Done` via `GateEvaluationService` is deferred to KBT-INI032 Epic D; until then the Done-transition is a manual `update_issue_status(status: "Done")` call (the standard Done-readiness gate still applies).

### Backend

- New `IssueStatus.InDeployment = 7` (append, no renumber per KBT-BD076). `Issue.UpdateStatus` blocks `InDeployment → InProgress` and `InDeployment → Cancelled` with structured `BusinessException` (`Kanbantic:InvalidTransitionFromInDeployment`) — use `Review` for rollback or `Done` for post-deploy completion.
- `IssueReadinessService` accepts `InDeployment` as a target with no checks at the issue layer (KBT-RL053: the merge itself is the gate).
- New `InDeploymentBackfillSeeder` runs once at API startup and bulk-promotes pre-existing `Review`-issues whose feature-branch is already merged on main, via `ExecuteUpdateAsync` (no `ChangeHistory`-spam).

### MCP tool descriptions

- `update_issue_status`, `list_issues`, `claim_issue` now mention `InDeployment` and the new lane-flow.
- `bootstrap_agent` description includes the 8-status lane-flow.

## Backwards-compat

- **No breaking changes** for plugins, MCP consumers, or DB-stored data:
  - `IssueStatus` enum value `InDeployment = 7` (append, not insert; pre-F3 numeric values unchanged) — KBT-BD076.
  - Direct `Review → Done` transition remains allowed at the API layer (`update_issue_status(status: "Done")` from Review still works) for legacy callers — but the plugin-skill prefers the two-step `Review → InDeployment → Done` for traceability.
  - Existing `Review`-issues whose branch is already merged are migrated automatically by `InDeploymentBackfillSeeder` on first post-deploy startup.

## Migration guide for agents

If your custom workflow relied on `kanbantic-issue-review` ending on `Done`:

1. **Adopted by default** — running v2.3.0's `kanbantic-issue-review` will leave the issue on `InDeployment`. Continue with the deploy-webhook + smoke-test + `update_issue_status(status: "Done")` sequence.
2. **Direct `Review → Done` still works** — `update_issue_status(status: "Done")` from Review continues to function for legacy callers, but you lose the visual distinction on the board between "merged but not deployed" and "live in prod".

## Cross-links

- KBT-F236 — backend Feature
- KBT-SR268 / KBT-RL053 / KBT-SR269 / KBT-BD076 / KBT-SR270 — backing specs
- KBT-US522 — user story
- KBT-PATN018 — updated lane-flow Pattern in the workspace toolkit
- KBT-GTCH027 — new Gotcha: InDeployment ≠ Done; first deploy-verify, then Done
