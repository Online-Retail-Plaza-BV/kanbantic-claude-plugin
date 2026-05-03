---
name: kanbantic-epic-proposal
description: "Use when the user wants to propose a new Epic. Lightweight intake: captures title, context / motivation, coarse scope, initiative (optional), release (optional), priority — then creates an Epic issue in status New. Does not create phases, implementation plan, or specs; those come later via kanbantic-issue-prepare."
user_invocable: true
command: propose-epic
---

# Kanbantic Epic Proposal

## Overview

Lightweight Epic intake. Capture the minimum needed to create an Epic issue in `New`, then hand off to the triage skill. Epics are wider than Features — the intake captures context and motivation, not a full plan. Implementation plan, phases, and tasks come later via `kanbantic-issue-prepare`.

**Principle:** Gather the essentials → Create Epic in Kanbantic (status `New`) → point at `kanbantic-issue-triage` for go/no-go.

**Announce at start:** "I'm using the kanbantic-epic-proposal skill to capture this Epic idea."

## Scope

- Creates exactly **one** issue via a single `create_issue` call with `type: "Epic"` and `status: "New"`.
- Does **not** create implementation plans, phases, tasks, specifications, user stories, or test cases — all of that is `kanbantic-issue-prepare`'s job after triage.
- Does **not** dispatch subagents. One short dialogue, one MCP call.
- Does **not** touch existing issues.

## Checklist

1. **Orient** — load workspace context
2. **Gather** — max 6 short questions, one at a time
3. **Confirm** — show summary, get approval
4. **Persist** — one `create_issue` call
5. **Handoff** — point at `kanbantic-issue-triage` + `kanbantic-issue-prepare`

## Step 1: Orient

```
MCP: mcp__kanbantic__get_context
```

Note the workspace ID, active initiatives, releases, and applications — needed for the `create_issue` call.

## Step 2: Gather

Ask **at most 6 questions**, one at a time, via `AskUserQuestion` with multiple-choice options where that helps. Skip questions the user already answered in their initial message.

| Field | Required | Notes |
|-------|----------|-------|
| Title | Yes | Short, outcome-oriented |
| Context / motivation | Yes | Why this Epic matters now, what changed |
| Coarse scope | Yes | 1-paragraph sketch of size and boundaries — not a detailed plan |
| Initiative | No | Link to a parent Initiative if one fits; else leave null |
| Release | No | Omit → issue lands in backlog |
| Priority | No | Critical / High / Medium / Low — default Medium |

**Application is intentionally optional** for Epic intake (per the Decision): Epics can be cross-application. The application (if any) is locked in during `kanbantic-issue-prepare`.

<HARD-GATE>
If Title, Context, or Coarse scope is missing after the dialogue, the skill **refuses** to create the issue. Report which field is missing and ask the user to supply it.
</HARD-GATE>

<HARD-GATE>
The skill MUST NOT call `create_specification`, `create_test_case`, `create_user_story`, `create_phase`, `add_task`, or `create_implementation_plan`. Intake captures nothing but the issue itself — everything else is `kanbantic-issue-prepare`'s territory.
</HARD-GATE>

## Step 3: Confirm

Present a short summary:

```
**Epic:** [title]
**Initiative:** [initiative name or "—"]
**Release:** [release name or "backlog"]
**Priority:** [priority]

## Context
[context]

## Coarse scope
[scope]

Zal ik dit Epic-issue aanmaken in status New?
```

Wait for confirmation before Step 4.

## Step 4: Persist

Exactly **one** MCP call. Format the description as structured Markdown:

```markdown
## Context

[context]

## Coarse scope

[scope]
```

```
MCP: mcp__kanbantic__create_issue(
  workspaceId: <workspace ID>,
  releaseId: <release id or null for backlog>,
  type: "Epic",
  title: <title>,
  description: <structured markdown description>,
  priority: <priority>,
  initiativeId: <initiative id or null>
)
```

The issue lands in status `New` — Kanbantic's default. Intake never auto-triages.

## Step 5: Handoff

Report:

**"Epic [CODE] has been created in status New. Next steps in the v0.10.0 lane-flow (8 statuses, 4 lane-skills):**

1. **Triage** — run `kanbantic-issue-triage` for the go / no-go decision (`New → Triaged`); confirm application, initiative, release, and priority.
2. **Prepare** — once Triaged, run `kanbantic-issue-prepare` to work out specs, user stories, and the full implementation plan (phases + tasks + code instructions) in one sequential skill-run (`Triaged → Prepared` on green readiness — Prepared is the dedicated ready-to-claim status since plugin v2.2.0 / KBT-F235).
3. **Execute** — `kanbantic-issue-execute` claims the Prepared Epic (atomic `Prepared → InProgress`) and implements phase by phase with per-phase review gates.
4. **Review + Deploy** — `kanbantic-issue-review` reviews + merges + transitions to `InDeployment` (since plugin v2.3.0 / KBT-F236); deploy webhooks + manual `update_issue_status(status: \"Done\")` complete the journey to `Done`."

No other MCP calls. Stop after printing the handoff.

## Key Principles

- **Fast** — max 6 questions, no design phases, no subagents
- **One create_issue call** — never more, never anything else
- **Issue lands in New** — triage is a separate lane, do not skip it
- **Application is optional at intake** — Epics can be cross-application; locked in during prepare
- **Noun-phrase skill name** — consistent with `kanbantic-bug-report` / `kanbantic-feature-request` for the intake trio
- **Never creates specs, user stories, test cases, phases, plans** — those belong to `kanbantic-issue-prepare`
