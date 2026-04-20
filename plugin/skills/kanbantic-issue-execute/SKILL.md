---
name: kanbantic-issue-execute
description: "Use when a Kanbantic issue needs to be implemented (Triaged + ready to claim). For Epics: executes the Implementation Plan phase by phase with per-phase push. For Features/Bugs: executes tasks directly without phases. Ends at status Review — handoff to kanbantic-issue-review for merge/close."
---

# Kanbantic Issue Execute

## Overview

Execute implementation work for any issue type. Handles two modes:
- **Epics**: execute the Implementation Plan phase by phase, push after each phase, request per-phase review
- **Features / Bugs**: execute tasks directly without phases; single push + handoff at the end

**Principle:** Claim issue (InProgress) → Read tasks + knowledge from Kanbantic → Implement code → Push → Update status + knowledge in Kanbantic. Stop at Review.

**Announce at start:** "I'm using the kanbantic-issue-execute skill to implement this issue."

## Scope

This skill owns the **InProgress → Review** transition. It does NOT merge, close the issue, or finalize knowledge extraction — those belong to `kanbantic-issue-review` and run after a positive review verdict.

## Checklist

1. **Gate-check** — verify issue is Triaged + ready to claim (HARD GATE)
2. **Claim issue** — set status to InProgress, record branch
3. **Load plan + knowledge** — get phases/tasks AND project patterns from Kanbantic
4. **Execute** — depends on issue type:
   - **Epic** (has Implementation Plan): execute per phase with per-phase push + review gates
   - **Feature / Bug** (no Implementation Plan): execute tasks directly
5. **Update knowledge** — store corrections or new discoveries in Toolkit/Library
6. **Run E2E tests** — invoke /test-e2e-local before completing (auto-trigger)
7. **Verify pre-conditions + transition to Review** — all tasks Done/Cancelled, all test cases Passed
8. **Handoff** — instruct user/agent to invoke `kanbantic-issue-review`

<HARD-GATE>
Tasks can ONLY be started (set to InProgress) when the parent issue is in **InProgress** status. If the issue is not InProgress, you MUST claim it first (Step 2) before working on any task. NEVER start a task on an issue that is still in New, Triaged, or any other non-InProgress status.
</HARD-GATE>

## Step 0: Ensure Repository Access

Before starting, verify you have local access to the workspace's code repository:

1. Run `git remote -v` to check if you're in a git repository
2. If already in the correct repository, skip to Step 1
3. If no repository or wrong repository:
   ```
   MCP: mcp__kanbantic__list_repositories(workspaceId)
   ```
   If the issue has an `applicationId`, choose the repository linked to that application. Otherwise use the first active repository.
   ```
   MCP: mcp__kanbantic__get_repository(repositoryId)  // → includes cloneUrl, gitAuthorName, gitAuthorEmail
   MCP: mcp__kanbantic__get_repository_credential(repositoryId)  // → PAT token for authentication
   ```
   Then clone and configure:
   ```bash
   git clone https://<credential>@github.com/<org>/<repo>.git
   cd <repo>
   git config user.name "<gitAuthorName>"
   git config user.email "<gitAuthorEmail>"
   ```

<IMPORTANT>
- If no repository is configured in the workspace, skip this step and proceed — not all work requires code access.
- If no credential is configured, tell the user: "No repository credential found. Configure a PAT token via Workspace → Repositories → Credentials in the Kanbantic UI."
- If the repo is already cloned, run `git pull` to get the latest code. Branch creation happens in Step 2.
</IMPORTANT>

## Step 1: Gate-check — Triaged + Ready to Claim

Before claiming, verify the issue is in the right state and has the required artifacts:

```
MCP: mcp__kanbantic__get_issue(issueId)
```

Inspect the response:

<HARD-GATE>
- **`status`**: MUST be `Triaged`. If the issue is in `New`, stop and tell the user:
  > "This issue is still `New`. Triage it first via the `kanbantic-issue-triage` skill before execution can start."
  If the issue is in `InProgress` already, resume execution from Step 3. Any other status (Review, Done, Cancelled) → stop and ask the user what they want.
- **`isReadyToClaim`**: MUST be `true`. If `false`, check `readinessChecks`:
  - **Hard enforcement**: STOP. Tell the user which checks failed and redirect them to `kanbantic-issue-prepare` to supply the missing artifacts (specifications / test cases / user stories) before execution can start. Do not proceed.
  - **Soft enforcement**: Warn the user which checks failed. Ask if they want to override. If yes, collect an `overrideReason` to pass in Step 2.
</HARD-GATE>

The explicit `Triaged` check prevents execution of half-designed issues and couples this skill to the output of `kanbantic-issue-triage`. The explicit `isReadyToClaim` check prevents bypassing readiness gates.

## Step 2: Claim Issue and Create Branch

```
MCP: mcp__kanbantic__claim_issue(issueId, branch: "<branch-name>", overrideReason: "<if soft override>")
```

Branch naming convention: `feature/<issue-code>-<short-slug>` for Features/Epics, `fix/<issue-code>-<short-slug>` for Bugs. The slug is a lowercase, hyphen-separated summary (max ~40 chars).

Examples:
- `feature/KBT-F163-issue-execute-rename`
- `fix/KBT-B170-popover-width`

Create the branch locally:
```bash
git checkout -b feature/<issue-code>-<slug>
```

## Workflow by Issue Type

Not all issues follow the full phase workflow:

- **Bug**: Simplified workflow — NO implementation plan or phases. Load tasks directly, execute all fix tasks, then transition to Review.
- **Feature**: Optional plan. If an implementation plan exists, follow the full phase workflow. If no plan exists, load tasks directly and execute them (skip phase-related steps 4A.1, 4A.3, 4A.4).
- **Epic**: Full workflow required — implementation plan with phases, per-phase review.

## Step 3: Load Tasks + Project Knowledge

### 3a: Load from Kanbantic

First, determine the issue type:
```
MCP: mcp__kanbantic__get_issue(issueId)
```

**If Epic** (has Implementation Plan):
```
MCP: mcp__kanbantic__get_implementation_plan(issueId)
MCP: mcp__kanbantic__list_tasks(issueId)
MCP: mcp__kanbantic__list_discussion_entries(issueId)
```

Read:
- **Phases**: ordered list of work phases
- **Tasks**: per phase, what to implement
- **Discussion entries** (KnowledgeExtraction): code instructions with file paths, snippets, line numbers

The KnowledgeExtraction entries contain the detailed code — use these as your implementation guide.

**If Feature / Bug** (no Implementation Plan):
```
MCP: mcp__kanbantic__list_tasks(issueId)
MCP: mcp__kanbantic__list_discussion_entries(issueId)
```

Read existing tasks and discussion context. If no tasks exist yet, you'll create them during execution (Step 4B.1).

### 3b: Load Project Knowledge from Kanbantic

```
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "ClaudeMd")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Pattern")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Gotcha")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Rule")
```

Load project-specific development guidance (ClaudeMd) first — these contain CLAUDE.md-style instructions that apply to all work in this workspace.

Optionally, if this issue touches architectural areas, read relevant Library documents:
```
MCP: mcp__kanbantic__list_library_documents(workspaceId, categoryType: "Architecture")
MCP: mcp__kanbantic__read_library_document(documentId)  // for relevant docs
```

This gives you codebase patterns, known pitfalls, and architecture context.

<IMPORTANT>
Do NOT launch Explore agents or do broad codebase exploration. The plan (tasks + KnowledgeExtraction entries) combined with Toolkit patterns and Library docs contain everything needed. Only do targeted file reads (Read tool) for specific files referenced in task descriptions when you need to see current line numbers or verify context.
</IMPORTANT>

## Step 4A: Execute Per Phase (Epics only)

Use this step for **Epics** that have an Implementation Plan with phases.

For each unlocked phase:

### 4A.1: Unlock Phase (if needed)

First phase is auto-unlocked. Subsequent phases unlock after the previous is approved:
```
MCP: mcp__kanbantic__unlock_phase(issueId, phaseId)
```

### 4A.2: Execute Tasks

<IMPORTANT>
Before starting any task, verify the issue is **InProgress**. If not, go back to Step 2 and claim it first.
</IMPORTANT>

For each task in the phase:

**Start:**
```
MCP: mcp__kanbantic__update_task_status(issueId, taskId, status: "InProgress")
```

**Implement:**
- Read the task description and the KnowledgeExtraction discussion entry for this phase
- Write the code exactly as specified
- Run build/test commands to verify
- Fix any issues

**Complete:**
```
MCP: mcp__kanbantic__update_task_status(issueId, taskId, status: "Done")
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: "**Task [title] completed.**\n\nChanges:\n- [files changed]\n\nVerification:\n- [build/test results]",
  entryType: "Comment"
)
```

**Commit after each task or logical group (conventional commits):**
```bash
git add <specific files>
git commit -m "<type>(<issue-code>): <task description>"
```

Use conventional-commit types:
- `feat` — new functionality
- `fix` — bug fix (use for Bug issues)
- `refactor` — refactor without behavior change
- `docs` — documentation only
- `test` — tests only
- `chore` — infrastructure / tooling

### 4A.3: Push Phase + Mark for Review

After all tasks in the phase are Done, **push the branch** so the reviewer can fetch it:

```bash
git push origin <branch>
```

Then mark the phase ready for review:
```
MCP: mcp__kanbantic__mark_phase_for_review(issueId, phaseId)
```

### 4A.4: Request Code Review

Invoke `kanbantic-issue-review` to review the phase:
```
Skill: kanbantic-issue-review
```

### 4A.5: Handle Review Result

- **Approved**: proceed to next phase (unlock via 4A.1, repeat)
- **Rejected**: read rejection reason, pick up the fix tasks the reviewer added, fix issues, commit, push, re-submit the phase for review

## Step 4B: Execute Tasks Directly (Features / Bugs)

Use this step for **Features** and **Bugs** that do NOT have an Implementation Plan.

<IMPORTANT>
Before starting any task, verify the issue is **InProgress**. If not, go back to Step 2 and claim it first.
</IMPORTANT>

### 4B.1: Create Tasks (if none exist)

If the issue has no tasks yet, analyze the issue description, specifications, and discussion entries, then create tasks:

```
MCP: mcp__kanbantic__add_task(
  issueId: <id>,
  title: "<action-oriented task title>",
  description: "<what to do>",
  priority: "High" | "Medium" | "Low"
)
```

### 4B.2: Execute Tasks

For each task:

**Start:**
```
MCP: mcp__kanbantic__update_task_status(issueId, taskId, status: "InProgress")
```

**Implement:**
- Read the task description and relevant discussion entries
- Write the code
- Run build/test commands to verify

**Complete:**
```
MCP: mcp__kanbantic__update_task_status(issueId, taskId, status: "Done")
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: "**Task [title] completed.**\n\nChanges:\n- [files changed]\n\nVerification:\n- [build/test results]",
  entryType: "Comment"
)
```

**Commit after each task or logical group (conventional commits):**
```bash
git add <specific files>
git commit -m "<type>(<issue-code>): <task description>"
```

### 4B.3: Push Branch

After all tasks are Done, push the branch so the reviewer can fetch it:
```bash
git push origin <branch>
```

## Step 5: Update Knowledge Base

After all phases are implemented (before Step 6), update the project knowledge:

### 5a: Correct Outdated Patterns

If any Toolkit pattern was incorrect or outdated during implementation:
```
MCP: mcp__kanbantic__update_toolkit_item(id, title, content: "<corrected pattern>")
```

### 5b: Add New Discoveries

If you discovered new reusable patterns, gotchas, or rules during implementation:
```
MCP: mcp__kanbantic__create_toolkit_item(
  workspaceId: <id>,
  category: "Pattern" | "Gotcha" | "Rule",
  title: "<descriptive name>",
  content: "<pattern with file paths, code example, when to use>"
)
```

### 5c: Deactivate Obsolete Knowledge

If a pattern no longer applies:
```
MCP: mcp__kanbantic__update_toolkit_item(id, title, content, isActive: false)
```

**Guidelines:**
- Only store patterns reusable across multiple issues
- Include file paths and code examples in every Toolkit item
- Update rather than duplicate — search existing items first
- Skip this step if nothing new was discovered (don't force it)

### 5d: Record Knowledge Traceability

Add a discussion entry documenting which Toolkit/Library items were consumed during execution and any changes made:

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId: <id>,
  content: <knowledge summary>,
  entryType: "KnowledgeExtraction"
)
```

Use this template:

```markdown
## Knowledge Trace — Execution

### Consumed (knowledge used during implementation)
- `KBT-PATN001` — ABP AppService pattern (Phase 1, 2)
- `KBT-GTCH003` — DI scoping in MCP tools (Phase 2)

### Produced (new discoveries during implementation)
- `KBT-PATN008` — SignalR hub registration pattern (new)

### Corrected
- `KBT-PATN002` — File path was outdated, updated to new location

### No knowledge changes
(Use this line instead if nothing was consumed, produced, or corrected)
```

This creates traceability between the issue and knowledge base — visible in the issue's discussion timeline in the Kanbantic UI.

## Step 6: Run Local E2E Tests (auto-trigger)

After all tasks are Done and knowledge is updated, run the local E2E test suite before transitioning to Review.

### 6a: Check if skill exists

```
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Skill", search: "test-e2e-local")
```

If no `/test-e2e-local` Toolkit Skill exists in the workspace, **skip this step** and proceed to Step 7.

### 6b: Invoke the skill

Load the Toolkit Skill content and execute the flow it describes:
- Issue code: use the current issue code (e.g., `KBT-F122`)
- Default test suite: `e2e/crud-functional.spec.ts`
- No `--with-mcp` unless the issue touches MCP tools

### 6c: Handle results

**If E2E tests pass:**
- Add discussion entry: "Local E2E tests passed — proceeding to Review pre-conditions."
- Continue to Step 7

**If E2E tests fail:**
- Issue remains **InProgress** (do NOT transition to Review)
- Add discussion entry with failure details
- Create fix tasks based on the failure details:
  ```
  MCP: mcp__kanbantic__add_task(issueId, title: "Fix E2E failure: {test name}", description: "{error details}", priority: "High")
  ```
- Report to user: "E2E tests failed. Created fix tasks. Issue remains InProgress."
- After fix tasks are completed, re-run this step

**If E2E infrastructure is unavailable** (PostgreSQL not installed, ports permanently occupied):
- Add discussion entry: "Local E2E tests skipped — {reason}"
- Warn the user and proceed to Step 7 (do not block the workflow)

## Step 7: Verify Review Pre-conditions + Transition

<HARD-GATE>
Review transition is allowed **only** when all of the following are true. If any condition fails, the issue stays `InProgress`, and the skill reports the failing condition to the user. NO "door-drukken".

1. Every task on the issue has status `Done` or `Cancelled`.
2. Every test case linked to the issue has status `Passed`.
3. Readiness checks on the issue still pass (`isReadyToClaim` was true at claim time; re-check in case specs/test cases were added mid-flight).
</HARD-GATE>

### 7a: Verify tasks

```
MCP: mcp__kanbantic__list_tasks(issueId)
```

Every task must be `Done` or `Cancelled`. For every `Cancelled` task, verify a Decision discussion entry recorded the justification (required per Cancelling section below).

### 7b: Verify test cases

```
MCP: mcp__kanbantic__list_test_cases(issueId)
```

Every returned test case must have `status: "Passed"`. If any are in `Draft`, `Ready`, `Failed`, `Blocked`, or `Skipped`, stop and report:

> "Cannot transition to Review. Test cases still missing a `Passed` status:
> - `KBT-TC1234` — Draft
> - `KBT-TC1235` — Failed
>
> Run the test cases (manually or via the E2E skill), record results via `update_test_case(status: \"Passed\")` after verification, then re-run this step."

### 7c: Re-check readiness

```
MCP: mcp__kanbantic__get_issue(issueId)
```

Confirm `isReadyToClaim` is still true (or that soft-override is acceptable). Report to the user if checks degraded.

### 7d: Transition

```
MCP: mcp__kanbantic__update_issue_status(issueId, status: "Review")
```

## Step 8: Final Report + Handoff

Report:
**"Implementation complete for [ISSUE CODE]. Status: Review.**

**Summary:**
- [N] tasks completed ([M] cancelled with justification)
- [N] commits on `feature/<issue-code>-<slug>`
- [N] test cases Passed
- Knowledge: [N] Toolkit items created/updated (if any)

**Next step:** Invoke `kanbantic-issue-review` to run code review, merge, close, and extract final knowledge."

Do **not** merge, do **not** set the issue to Done, do **not** create a PR — those are `kanbantic-issue-review`'s responsibilities.

## Subagent Mode

For large plans, you can dispatch implementer subagents per task. Use the template at `implementer-prompt.md` in this directory.

When using subagents:
1. Dispatch one subagent per task using the Agent tool
2. Review the subagent's output
3. Update task status in Kanbantic based on results
4. Commit + (for Epics) request review via 4A.3/4A.4

## Cancelling Tasks or Issues

<HARD-GATE>
When cancelling a task or issue, you MUST record the justification in a discussion entry BEFORE changing the status. Cancellation without recorded justification is NOT allowed.
</HARD-GATE>

**Cancelling a task:**
```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: "**Task [title] cancelled.** Reason: [clear justification why this task is no longer needed]",
  entryType: "Decision"
)
MCP: mcp__kanbantic__update_task_status(issueId, taskId, status: "Cancelled")
```

**Cancelling an issue:**
```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: "**Issue [code] cancelled.** Reason: [clear justification — e.g. superseded by X, no longer relevant because Y, duplicate of Z]",
  entryType: "Decision"
)
MCP: mcp__kanbantic__update_issue_status(issueId, status: "Cancelled")
```

## Key Principles

- **Follow the plan** — implement exactly what's specified
- **One task at a time** — don't skip ahead
- **Verify before completing** — build and test after each task
- **Commit frequently** — one commit per task or logical unit, conventional commits
- **Push per phase (Epics) or at end (Feature/Bug)** — never leave work only local
- **Update Kanbantic** — status changes and discussion entries for visibility
- **Justify cancellations** — always record why in a Decision discussion entry
- **Stop at Review** — merge/close/knowledge-finalize is `kanbantic-issue-review`'s job
- **Stop when blocked** — ask questions, don't guess
