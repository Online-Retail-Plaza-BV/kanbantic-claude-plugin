---
name: kanbantic-issue-prepare
description: "Use after kanbantic-issue-triage marks an issue Triaged. Consolidates the old design + debugging + planning flows into one lane-verwerker. Routes on issue.type: Feature → requirements + specs + test cases; Bug → root-cause + repro-steps + regression test; Epic → requirements + implementation plan (phases + tasks). Ends by transitioning the issue to Prepared (KBT-F235) once all readiness-checks pass — the issue then sits in the Prepared kanban-column awaiting claim_issue from kanbantic-issue-execute."
---

# Kanbantic Issue Prepare

## Overview

`kanbantic-issue-prepare` works a Triaged issue all the way to a first-class **`Prepared`** status (KBT-F235). It is the **single entry point** for the Triaged → Prepared lane transition — regardless of whether the issue is a Feature, Bug, or Epic. Internally it dispatches on `issue.type` so the user never has to choose a sub-skill.

**Principle:** Read Triaged issue from Kanbantic → route on type → dialogue with user → write specs / user stories / test cases / phases to Kanbantic → transition issue to `Prepared` so it surfaces in the Prepared kanban-column for claim_issue.

**Announce at start:** "I'm using the kanbantic-issue-prepare skill to work this issue out until it's claimable."

## Scope

This skill owns the **Triaged → Prepared** transition. It does NOT:

- Create new issues — that is the job of the intake skills (`kanbantic-feature-request`, `kanbantic-epic-proposal`, `kanbantic-bug-report`). If the user proposes a completely new idea mid-dialogue, the skill points them at the right intake skill and stops.
- Change issue status to `InProgress` — that is the job of `kanbantic-issue-execute` (which now claims directly from `Prepared` via `claim_issue`, atomically promoting status to `InProgress` per KBT-RL052).

If the readiness-gate is still not green at the end of a run, the issue stays on `Triaged` (no transition) and the skill reports which checks are still failing — the user re-runs the skill once the missing artifacts are added.

## Checklist

1. **Gate-check** — verify issue is Triaged (HARD GATE)
2. **Load issue context** — issue, linked specs, test cases, user stories, readiness-checks
3. **Load shared project knowledge** — Toolkit (ClaudeMd, Rules, Patterns, Gotchas) + Library (Architecture)
4. **Route on `issue.type`**:
   - **Feature** → Step 5F (requirements-dialoog)
   - **Bug** → Step 5B (root-cause-dialoog)
   - **Epic** → Step 5E (requirements + implementation plan, sequentieel)
5. **Validate readiness** — re-check `isReadyToClaim`; report failing checks or confirm ready
6. **Record Decision entry** — summary of what was added in this run
7. **Handoff** — instruct user to invoke `kanbantic-issue-execute`

<HARD-GATE>
Step 1 blocks execution when the issue is not Triaged:

- `New` → redirect to `kanbantic-issue-triage` and stop
- `InProgress`, `Review`, `Done`, `Cancelled` → stop and ask the user what they want (prepare is not a re-work skill)

Only Triaged issues are accepted.
</HARD-GATE>

<HARD-GATE>
This skill must NEVER call `create_issue`. If during the dialogue the user brings up a completely new, unrelated idea, the skill says:

> "Dit lijkt een nieuw issue. Gebruik `kanbantic-feature-request`, `kanbantic-epic-proposal` of `kanbantic-bug-report` om het aan te maken, en kom daarna terug naar prepare."

Then the skill stops. Allowed MCP writes are: `create_specification`, `create_test_case`, `create_user_story`, `create_phase`, `add_task`, `add_discussion_entry`, `create_implementation_plan`, `update_issue` (for description clarification).
</HARD-GATE>

## Step 0: Ensure Repository Access

Before starting, verify you have local access to the workspace's code repository:

1. Run `git remote -v` to check if you're in a git repository
2. If already in the correct repository, skip to Step 1
3. If no repository or wrong repository:
   ```
   MCP: mcp__kanbantic__list_repositories(workspaceId)
   ```
   Pick the repo linked to the issue's `applicationId`, or the first active repository.
   ```
   MCP: mcp__kanbantic__get_repository(repositoryId)
   MCP: mcp__kanbantic__get_repository_credential(repositoryId)
   ```
   Then clone (read-only access is enough for prepare) and stay on the default branch:
   ```bash
   git clone https://<credential>@github.com/<org>/<repo>.git
   cd <repo>
   git checkout main && git pull
   ```

<IMPORTANT>
Prepare does not create branches or commits. It only reads the codebase for context and writes to Kanbantic via MCP.
</IMPORTANT>

## Step 0.5: Worktree HARD-GATE

<HARD-GATE>
Before any status-mutating or artifact-creating step, verify you are **not** in the main working tree. Agents often run in parallel on the same clone; prepare may write code instructions and temporary files — working in the main tree on a feature branch risks conflicts with other concurrent agents.

```bash
GIT_DIR=$(git rev-parse --git-dir)
GIT_COMMON=$(git rev-parse --git-common-dir)
if [ "$GIT_DIR" = "$GIT_COMMON" ]; then
  STOP. Report to user verbatim:
  "You are in the main working tree ($GIT_COMMON).
  Run EnterWorktree(name: '<ISSUE-CODE>') first, then re-run this skill.
  See KBT-TRUL004 for the rationale."
fi
```

`<ISSUE-CODE>` is the code of the issue this skill is processing (e.g. `KBT-F123`).

**No opt-out, no override.** This is a working-tree safety check, not a readiness-artifact check. Working in the main tree is wrong even if the specific bullet reasons don't apply right now — parallel agents are the norm, not the exception.

If the check passes (paths differ → you are in a worktree), continue silently.
</HARD-GATE>

## Step 1: Gate-check — Triaged

```
MCP: mcp__kanbantic__get_issue(issueId)
```

- If `status != "Triaged"` → stop per the HARD-GATE above.
- If the issue already satisfies `isReadyToClaim == true` and has all artifacts the type requires (see Step 5 per type), tell the user the issue is already fully prepared and offer to hand off to `kanbantic-issue-execute`.

## Step 2: Load Issue Context

```
MCP: mcp__kanbantic__list_specifications(workspaceId)
MCP: mcp__kanbantic__list_test_cases(issueId)
MCP: mcp__kanbantic__list_discussion_entries(issueId)
```

Read:
- Issue description (from Step 1)
- Linked specifications (existing ones — may already be there from intake or a previous prepare-run)
- Test cases already linked
- Any existing Decision / Comment / Question entries

## Step 3: Load Shared Project Knowledge

```
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "ClaudeMd")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Pattern")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Gotcha")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Rule")
MCP: mcp__kanbantic__list_library_documents(workspaceId, categoryType: "Architecture")
```

Read ClaudeMd first — that contains CLAUDE.md-style guidance that applies to any work in the workspace. Then Rules, Patterns, Gotchas. Read the most relevant Library (Architecture) documents if the issue touches those areas.

<IMPORTANT>
Do not launch broad Explore agents. Use targeted reads (Glob, Grep, Read) for specific files the issue mentions or that are referenced by relevant Toolkit patterns.
</IMPORTANT>

## Step 4: Route on `issue.type`

Dispatch based on `issue.type`:

- `Feature` → Step 5F
- `Bug` → Step 5B
- `Epic` → Step 5E

For any other type, stop and report: "Unknown issue type `<type>`. Prepare supports Feature, Bug, and Epic only."

## Step 5F: Feature — Requirements Dialogue

Goal: end with enough `ProductRequirement` / `SystemRequirement` / `Rule` / `Boundary` specs + test cases + at least one user story so `isReadyToClaim == true`.

### 5F.1: Clarify purpose

Ask questions one at a time (multiple-choice via `AskUserQuestion` where possible):

- What problem does this feature solve?
- Who uses it and how?
- What's in scope? What's explicitly out of scope?
- Performance / compatibility / existing-pattern constraints?
- Success criteria?

### 5F.2: Propose approaches

Present 2–3 approaches with trade-offs (complexity, performance, maintainability). Lead with your recommendation.

### 5F.3: Design sections

Scale sections to complexity: Data model / Backend logic / Frontend UI / MCP integration. Ask after each section: "Ziet dit er goed uit?" / "Does this look right?"

### 5F.4: Write user story, specs, test cases

Per requirement:
```
MCP: mcp__kanbantic__create_user_story(workspaceId, issueId, ...)
MCP: mcp__kanbantic__create_specification(
  workspaceId, category: "ProductRequirement" | "SystemRequirement" | "SecurityRequirement" | "Rule" | "Boundary",
  title, content, extractedFromIssueId: issueId
)
MCP: mcp__kanbantic__create_test_case(
  workspaceId, title, description, steps, expectedResult,
  issueId, priority
)
```

Test-case test-levels should aim for Unit + Integration + E2E coverage where sensible — the Review → Done gate later enforces `Unit + Integration + E2E` diversity per `KBT-RL012`.

### 5F.5: Decision entry

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId, content: <design summary with chosen approach and rationale>,
  entryType: "Decision"
)
```

Go to Step 6.

## Step 5B: Bug — Root-Cause Dialogue

Goal: end with a reproducible bug, a clear hypothesis (or confirmed root cause) captured in a Comment entry, and at least one regression test case.

<HARD-GATE>
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST. If the user wants a quick fix, push back: prepare produces the understanding, `kanbantic-issue-execute` produces the fix.
</HARD-GATE>

### 5B.1: Reproduce

Ask:
- Steps to reproduce (exact sequence)?
- Expected vs actual?
- Can you trigger it reliably? If not, gather more data before guessing.

### 5B.2: Investigate — the four phases

1. **Read error messages carefully** — stack traces, line numbers, error codes
2. **Check recent changes** — `git log --oneline -20` (on main) to see what changed
3. **Check known gotchas** — from the Toolkit loaded in Step 3
4. **Trace data flow** — where does the bad value originate? Fix at source, not symptom

### 5B.3: Pattern analysis

- Find similar working code
- List every difference between working and broken
- Identify dependencies

### 5B.4: Hypothesis

Form a testable hypothesis: "I think X is the root cause because Y." Capture in a `Comment` discussion entry so `kanbantic-issue-execute` can verify it.

### 5B.5: Regression test case

Create at least one test case covering the failing scenario:
```
MCP: mcp__kanbantic__create_test_case(
  workspaceId,
  title: "Regression: [bug description]",
  description: "Verifies that [bug] is fixed",
  steps: "[steps to verify]",
  expectedResult: "[expected behavior after fix]",
  issueId, priority: "High"
)
```

### 5B.6: Decision entry

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: "## Root cause hypothesis\n\n**Symptom:** ...\n**Hypothesis:** ...\n**Evidence:** ...\n**Proposed fix direction (not yet implemented):** ...",
  entryType: "Decision"
)
```

Go to Step 6.

## Step 5E: Epic — Sequential Design + Implementation Plan

<HARD-GATE>
For Epics, Steps 5E.1–5E.4 (design) and 5E.5–5E.8 (plan) MUST run in sequence within the same skill-run. Splitting across two invocations leaves the Epic half-prepared and produces a stuck Triaged state. If the skill is interrupted, the user restarts it from the top.
</HARD-GATE>

### 5E.1–5E.3: Requirements dialogue

Same as Step 5F.1–5F.3 but applied at Epic scope (wider purpose, broader trade-offs).

### 5E.4: Write Epic-level user stories, specs, test cases

Same as Step 5F.4 but typically more specs and at least one user story per high-level capability.

### 5E.5: Create implementation plan

```
MCP: mcp__kanbantic__create_implementation_plan(
  issueId, title: "<Issue Code> Implementation Plan"
)
```

### 5E.6: Design phases

Group tasks into logical phases (2–5 tasks per phase). Dependencies first: backend before frontend, model before service.

```
MCP: mcp__kanbantic__create_phase(
  issueId, name: "<phase name>", description: "<what this phase covers>"
)
```

### 5E.7: Create tasks + code instructions per phase

Per task:
```
MCP: mcp__kanbantic__add_task(
  issueId, phaseId, title, description, priority
)
```

Per phase, add a `KnowledgeExtraction` discussion entry containing **complete code instructions**:
- Files to modify/create (exact paths)
- Code snippets showing what to add/change
- Line numbers where changes go
- Build/test commands to verify
- Expected results

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: <full code instructions in Markdown>,
  entryType: "KnowledgeExtraction"
)
```

### 5E.8: Decision entry

Summarize phase breakdown, key architectural choices, and the rationale.

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId, content: <summary>, entryType: "Decision"
)
```

Go to Step 6.

## Step 6: Validate Readiness

```
MCP: mcp__kanbantic__get_issue(issueId)
```

Re-inspect `readinessChecks` for the `Triaged → Prepared` transition. The `isReadyToClaim` boolean on the DTO is now derived from `Status == Prepared` (KBT-SR266) — at this point it is still `false`; that flips to `true` after Step 6a transitions the issue.

### 6a: All checks green — transition to Prepared

```
MCP: mcp__kanbantic__update_issue_status(issueId, status: "Prepared")
```

The backend evaluates `Triaged → Prepared` readiness (KBT-RL051): all required checks must be green, otherwise a structured `ReadinessGateBlocked` (Hard) or `ReadinessGateSoftBlock` (Soft) BusinessException with `recommendation` is returned — pattern-match on `(missingCondition: ...)` to fix and retry, do not blindly retry.

If the transition succeeds, report:

**"[ISSUE CODE] transitioned to `Prepared`. All readiness checks pass:**
- HasDescription: ✓
- UserStories: ✓ (N linked)
- Specifications: ✓ (N linked)
- TestCases: ✓ (N linked)

**Next step:** Invoke `kanbantic-issue-execute`. It will call `claim_issue(branch: ...)` which atomically assigns the issue and promotes `Prepared → InProgress` in a single MCP call (KBT-RL052)."

### 6b: Some checks still failing

Do **not** call `update_issue_status(Prepared)` — the gate would reject it. The issue stays on `Triaged`. Report exactly which checks are still failing and what's needed; offer to continue the dialogue or stop. Re-run the skill after the missing artifacts are added.

## Step 7: Handoff

If 6a fires: issue is `Prepared`; hand off to `kanbantic-issue-execute`. If 6b fires: issue stays `Triaged` until the missing artifacts are added.

## Key Principles

- **One skill, type-based routing** — the user doesn't choose between design / debugging / planning
- **Triaged → Prepared**, nothing more, nothing less (KBT-F235)
- **Never create new issues** — intake skills do that
- **Epics are sequential design+plan in one run** — leaving a half-prepared Epic is a failure mode
- **Root cause before fix (Bug)** — prepare captures understanding, execute captures the fix
- **Readiness gate is the exit criterion** — the skill is done when `isReadyToClaim == true`
- **Kanbantic is source of truth** — everything persists via MCP
