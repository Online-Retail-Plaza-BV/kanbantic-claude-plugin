# Kanbantic Claude Plugin v2.0.0 — Lane Workflow Skills

This release completes the lane-workflow-skills redesign tracked in Kanbantic Initiative **KBT-INI033**. The plugin's skill set now maps one-to-one onto the Kanbantic issue lanes: **New → Triaged → (ready-to-claim) → InProgress → Review → Done**.

**This is a MAJOR version bump (v1 → v2)** because five skill names have been renamed or retired with no aliases, no deprecation warnings, and no grace period. Any existing workflow that called the old names must be updated in the same commit as the plugin upgrade — invoking an old name returns "skill not found".

## New skills

### Intake (noun-phrase naming)
- **`kanbantic-feature-request`** — lightweight Feature intake. One short dialogue, one `create_issue` call, Feature issue lands in `New`.
- **`kanbantic-epic-proposal`** — lightweight Epic intake. Captures title + context + coarse scope; Epic issue lands in `New`.

Together with the unchanged `kanbantic-bug-report`, these form the intake trio.

### Lane-verwerkers (imperative-verb naming)
- **`kanbantic-issue-triage`** — go / no-go for the **New → Triaged** transition. Go: sets priority / release / application / initiative / tags. No-go: ≥20-char reason recorded as Decision entry, status to `Cancelled`.

## Consolidated skill

- **`kanbantic-issue-prepare`** — one skill covers the entire **Triaged → (ready-to-claim)** transition. Internally routes on `issue.type`:
  - **Feature** → requirements dialogue → user stories + specs + test cases
  - **Bug** → root-cause dialogue → repro-steps + hypothesis + regression test
  - **Epic** → sequential requirements + full implementation plan in one skill-run

## Renames (no aliases)

| Old name | New name | Change |
|----------|----------|--------|
| `kanbantic-issue-executing` | `kanbantic-issue-execute` | Rename + 7-point completeness-audit. New HARD-GATEs for Triaged / ready-to-claim start state and for Review pre-conditions (all tasks Done/Cancelled + all test cases Passed). |
| `kanbantic-code-review` | `kanbantic-issue-review` | Rename + merge-to-main + status-to-Done + optional knowledge-extractie. Skill now owns the full Review → Done lane. |
| `kanbantic-issue-design` | `kanbantic-issue-prepare` (Feature routing) | Retired — creation role moved to `kanbantic-feature-request`; elaboration role absorbed by `kanbantic-issue-prepare`. |
| `kanbantic-issue-planning` | `kanbantic-issue-prepare` (Epic routing) | Retired — planning is now the Epic branch of `kanbantic-issue-prepare`, executed sequentially with design. |
| `kanbantic-debugging` | `kanbantic-issue-prepare` (Bug routing) | Retired — investigation flow is now the Bug branch of `kanbantic-issue-prepare`. |

## Migration guide

Any existing prompts, documentation, CI scripts, or muscle-memory that called the old names must be updated. The plugin does not accept the old names — invocation returns "skill not found".

| If your script called… | Call instead |
|------------------------|--------------|
| `/design-issue` | `/request-feature` (intake) or `/prepare-issue` (elaboration) |
| `/plan-issue` | `/prepare-issue` (Epic routing) |
| `kanbantic-issue-executing` | `kanbantic-issue-execute` (or `/execute-issue`) |
| `kanbantic-code-review` | `kanbantic-issue-review` (auto-invoked from execute; no slash command) |
| `kanbantic-debugging` | `kanbantic-issue-prepare` (Bug routing) |

## Slash commands

- `/report-bug` — `kanbantic-bug-report` (unchanged)
- `/request-feature` — `kanbantic-feature-request` (new)
- `/propose-epic` — `kanbantic-epic-proposal` (new)
- `/triage-issue` — `kanbantic-issue-triage` (new)
- `/prepare-issue` — `kanbantic-issue-prepare` (new)
- `/execute-issue` — `kanbantic-issue-execute` (renamed)
- `kanbantic-issue-review` is auto-invoked from execute; no slash command

Removed: `/design-issue`, `/plan-issue`.

## Infrastructure

No changes to the stdio proxy, MCP server, or installation flow. `irm https://kanbantic.com/install.ps1 | iex` installs v2.0.0 as usual.

## Kanbantic tracking

All work tracked in Initiative **KBT-INI033**, release **v0.9.0 — Lane Workflow Skills**:

- `KBT-F160` — intake skills (feature-request + epic-proposal)
- `KBT-F161` — kanbantic-issue-triage
- `KBT-F162` — kanbantic-issue-prepare consolidation
- `KBT-F163` — kanbantic-issue-execute rename + audit
- `KBT-F164` — kanbantic-issue-review rename + merge/close/knowledge

All five Features are Done with every task and test case resolved; every linked specification is Approved.
