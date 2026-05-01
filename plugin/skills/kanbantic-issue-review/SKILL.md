---
name: kanbantic-issue-review
description: "Use after kanbantic-issue-execute marks an issue Review. Runs code review against Kanbantic specs + test cases. On approve: merges the feature branch to main, pushes, cleans up, transitions the issue to Done, and records an optional knowledge-extractie. On reject: leaves the issue on Review with fix tasks."
---

# Kanbantic Issue Review

## Overview

Complete the Review → Done lane transition. This skill:

1. Reviews completed implementation against Kanbantic specifications and test cases
2. Dispatches a reviewer subagent for categorized feedback
3. Approves or rejects the phase in Kanbantic
4. **On approve** — merges the feature branch to main, pushes, cleans up, transitions the issue to Done, and prompts for optional knowledge-extractie
5. **On reject** — records fix tasks and leaves the issue on Review for the implementer to iterate

**Principle:** Read specs from Kanbantic → Review code → Write feedback to Kanbantic → Merge / close / knowledge on positive verdict.

**Announce at start:** "I'm using the kanbantic-issue-review skill to review and close this issue."

## Checklist

1. **Load context** — issue, specifications, test cases, rules/patterns/gotchas
2. **Get diff** — what changed in this phase (or the whole issue for Feature/Bug)
3. **Dispatch reviewer** — subagent reviews against specs
4. **Record feedback** — discussion entry with categorized issues
5. **Decide** — approve or reject phase
6. **Verify final-approve gate** — merge only after last phase (Epic) or first approve (Feature/Bug)
7. **Merge** — `git merge --no-ff` to main, push, clean up feature branch
8. **Close issue** — transition to Done
9. **Knowledge-extractie (optional)** — toolkit items + document impacts + `KnowledgeExtraction` entry

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
4. Ensure you're on the branch being reviewed (`git checkout <feature-branch>`)

<IMPORTANT>
- If no repository is configured in the workspace, the review still runs against the spec+diff artifacts in Kanbantic, but merge/close cannot execute. Warn the user and continue without Step 7–8.
- If no credential is configured, tell the user: "No repository credential found. Configure a PAT token via Workspace → Repositories → Credentials in the Kanbantic UI."
- If the repo is already cloned, ensure you're on the branch being reviewed before proceeding.
</IMPORTANT>

## Step 0.5: Worktree HARD-GATE

<HARD-GATE>
Before any status-mutating, merge, or push step, verify you are **not** in the main working tree. Agents often run in parallel on the same clone; review performs `git merge --no-ff` and `git push origin main` — working in the main tree here risks overwriting concurrent changes or pushing unrelated state.

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

`<ISSUE-CODE>` is the code of the issue this skill is reviewing (e.g. `KBT-F123`).

**No opt-out, no override.** This is a working-tree safety check, not a readiness-artifact check. The merge step specifically re-enters the main branch to integrate; doing that from a worktree keeps the main clone untouched by the reviewer's local state.

If the check passes (paths differ → you are in a worktree), continue silently.
</HARD-GATE>

## Step 1: Load Context

```
MCP: mcp__kanbantic__get_issue(issueId)
```

Load the issue first so the status gate below can run on the actual current status, not a stale assumption.

## Step 1.5: Status HARD-GATE

<HARD-GATE>
The review skill owns the **Review → Done** transition. Any other starting status is out of scope. Verify `issue.status == "Review"` before doing anything that costs resources (reviewer subagent, git diff, discussion entries).

- If `status == "Review"` → continue silently.
- If `status == "New"` → STOP. Report: "Issue [CODE] is still in status `New`. Run `/triage-issue [CODE]` first to move it to Triaged."
- If `status == "Triaged"` → STOP. Report: "Issue [CODE] is Triaged but not yet executed. Run `/prepare-issue [CODE]` (if artifacts missing) and `/execute-issue [CODE]` before review can run."
- If `status == "InProgress"` → STOP. Report: "Issue [CODE] is still `InProgress`. `/execute-issue` must transition it to Review before review can run."
- If `status == "Done"` → STOP. Report: "Issue [CODE] is already `Done`. No review needed — this skill is an idempotent no-op here."
- If `status == "Cancelled"` → STOP. Report: "Issue [CODE] was `Cancelled`. Nothing to review."

**On any STOP**: exit the skill immediately. Do **NOT** dispatch the reviewer subagent (Step 3), do **NOT** create discussion entries (Step 4), do **NOT** attempt a status transition. This gate prevents resource-waste and misleading audit-trail entries on issues that are not in the Review lane.

No opt-out, no override — the skill's scope is by definition Review → Done.
</HARD-GATE>

## Step 1b: Load Review Context

```
MCP: mcp__kanbantic__list_specifications(workspaceId)
MCP: mcp__kanbantic__list_test_cases(workspaceId, issueId)
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Rule")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Pattern")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Gotcha")
```

Build a requirements checklist from specifications and test cases.

Include Rules, Patterns, and Gotchas in the review context — the reviewer should verify code adheres to project rules and follows established patterns.

## Step 2: Get Git Diff

```bash
# Diff for this phase (from phase start to current HEAD)
git log --oneline -10
git diff <phase-start-sha>..HEAD --stat
git diff <phase-start-sha>..HEAD
```

If reviewing the entire issue:
```bash
git diff main..HEAD --stat
git diff main..HEAD
```

## Step 3: Dispatch Reviewer Subagent

Use the reviewer template at `reviewer-prompt.md` in this directory.

Dispatch via Agent tool with `subagent_type: "general-purpose"`:
- Fill in the issue details, specifications, test cases, and diff
- The reviewer returns categorized feedback

## Step 4: Record Feedback in Kanbantic

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: <review feedback in Markdown>,
  entryType: "Comment"
)
```

Feedback format:
```markdown
## Code Review — Phase: [Phase Name]

### Strengths
- [What was done well]

### Issues

**Critical** (must fix before approval):
- [Issue description + file:line + recommendation]

**Important** (should fix):
- [Issue description + recommendation]

**Minor** (suggestions):
- [Nice-to-have improvements]

### Requirements Checklist
- [x] KBT-PR001: [requirement title] — implemented
- [ ] KBT-PR002: [requirement title] — not found
- [x] KBT-TC001: [test case title] — covered

### Verdict: APPROVE / REJECT
```

## Step 5: Approve or Reject

### 5a: If no Critical or Important issues — APPROVE

```
MCP: mcp__kanbantic__approve_phase(issueId, phaseId)
```

Proceed to Step 6.

### 5b: If Critical or Important issues found — REJECT

<IMPORTANT>
Rejection MUST always include a clear justification. The reason is recorded as a discussion entry and must explain what failed and what needs to change.
</IMPORTANT>

Create fix tasks:
```
MCP: mcp__kanbantic__add_task(
  issueId,
  title: "Fix: [issue description]",
  description: "[what to fix and how]",
  priority: "High"
)
```

Then reject with detailed reason:
```
MCP: mcp__kanbantic__reject_phase(
  issueId, phaseId,
  reason: "[N] critical and [N] important issues found: [list each issue briefly]. Fix tasks created."
)
```

<HARD-GATE>
On REJECT the skill stops here. Do NOT proceed to Step 6/7/8/9. No merge, no Done-transition, no knowledge-extractie. The issue stays on `Review` (or the backend may bounce it to `InProgress` automatically — follow the backend's default), and the implementer runs `kanbantic-issue-execute` again to pick up the fix tasks.
</HARD-GATE>

Report:
**"Review rejected for [ISSUE CODE]. [N] fix tasks created. Implementer can resume via `kanbantic-issue-execute` to address them."**

## Step 6: Verify Final-Approve Gate

<HARD-GATE>
The merge step only runs when the approved phase is the **final** approval needed for the whole issue. Tussentijdse phase-approvals in een Epic tonen voortgang maar leiden niet tot merge.

- **Epic**: merge only when **every** phase in the implementation plan has status `Approved`. Re-run `get_implementation_plan(issueId)` and verify all phases are approved.
- **Feature / Bug**: the first `approve_phase` on the issue-level is also the final approve — proceed to merge.

If this is **not** the final approve (Epic with remaining phases), report:
> "Phase [N/M] approved for [ISSUE CODE]. Remaining phases: [list]. No merge yet. Implementer continues with the next phase via `kanbantic-issue-execute`."

Then STOP. Do NOT proceed to Step 7/8/9. The issue stays on its current status (`Review` for the phase being approved; Kanbantic manages phase-vs-issue status internally).
</HARD-GATE>

## Step 7: Merge + Push + Cleanup

Execute the merge to main with a no-ff merge commit so the merge-historie zichtbaar blijft:

```bash
git checkout main
git pull origin main
git merge --no-ff <feature-branch> -m "Merge <ISSUE-CODE>: <short summary>"
git push origin main
```

Then clean up the feature branch:

```bash
git branch -d <feature-branch>           # local delete (blocking if it fails)
git push origin --delete <feature-branch> # remote delete (warning on failure, not blocker)
```

**Foutgevallen:**
- **Merge-conflict** → skill stops, lists the conflicting files, adds a Comment discussion entry to the issue explaining which files conflicted and that the issue stays on `Review`. The implementer resolves conflicts manually on the feature branch, pushes, and re-runs `kanbantic-issue-review`.
- **Push rejection** (branch protection, non-fast-forward, permissions) → skill reports the exact git error, adds a Comment discussion entry, and does **not** transition the issue to Done. No status change until merge + push both succeed.
- **Local branch delete failure** → blocker; investigate (usually uncommitted changes). Do not proceed.
- **Remote branch delete failure** → warning only (someone else may have deleted it, or branch protection prevents it). Log the warning in the issue and proceed to Step 8.

Use `--no-ff` as the default merge strategy. Do NOT use `--squash` or `--rebase` unless the workspace explicitly opts in via a Toolkit rule (auto-merge-beleid valt onder Execution Hardening, v0.6.0).

## Step 7.5: Record Review Approval

Before transitioning to Done, persist a `ReviewApproval` row so the
`HasReviewApproval` readiness-gate flips green. The approval captures the
reviewer-principal, verdict, and a written summary (≥20 chars) — the
audit-trail that KBT-F170 / KBT-PR191 made mechanically required after the
KBT-F156 / KBT-B175 incidents. Without this row the next step's
`update_issue_status(Done)` will fail with `ReadinessGateBlocked` /
`HasReviewApproval not met`.

```
MCP: mcp__kanbantic__approve_review(
  issueId,
  verdict: "Approved" | "ApprovedWithComments",
  reason: <≥20-char review summary — usually the body of the Decision entry from Step 4>
)
```

- Pick `Approved` for clean reviews, `ApprovedWithComments` when nits or
  follow-up tasks were noted but the issue is still ready for Done.
- Reuse the review-summary written in Step 4 (the Critical/Important/Minor
  verdict block) so the approval row and the discussion-entry stay in sync.
- The reason is required and validated to ≥20 characters after trim.

If `approve_review` fails (e.g. the issue is no longer in `Review` status
because someone bounced it back), stop the skill and report the error. Do
NOT proceed to Step 8 — the gate cannot clear without a successful approval.

## Step 8: Close Issue

<IMPORTANT>
Step 8 runs only after Step 7 completed successfully (merge **and** push both succeeded; local branch delete succeeded; remote delete is a warning-only) **and** Step 7.5 recorded a ReviewApproval row.
</IMPORTANT>

```
MCP: mcp__kanbantic__update_issue_status(issueId, status: "Done")
```

If the workspace's readiness gate blocks `Review → Done` (missing Specifications Approved / missing E2E test level / **missing Review Approved** / etc.), the call returns a `ReadinessGateBlocked` error. Surface the blocking checks to the user and stop — do **not** override without explicit instruction. The merge is already on main, so the issue stays on `Review` until the gate clears.

## Step 9: Knowledge-Extractie (optional)

After the issue is Done, prompt the reviewer for knowledge to capture. This step is **optional** — if the reviewer has nothing to add, skip the MCP calls.

### 9a: Toolkit items

Ask: **"Heb je patterns, gotchas of rules geleerd die de moeite waard zijn om vast te leggen?"**

If yes, per item collect:
- `title` (descriptive)
- `category` — `Pattern` | `Gotcha` | `Rule`
- `content` — Markdown with file paths, code example, when to use

Then:
```
MCP: mcp__kanbantic__create_toolkit_item(
  workspaceId: <id>,
  category: "Pattern" | "Gotcha" | "Rule",
  title: <title>,
  content: <content>
)
```

If a pattern already exists but is outdated, prefer `update_toolkit_item` (search first with `list_toolkit_items(search: ...)`).

### 9b: Document impacts

Ask: **"Zijn er Library-docs die door dit werk stale zijn geworden?"**

If yes, collect the document IDs (or names → look up via `list_library_documents`) and a short reason per doc:

```
MCP: mcp__kanbantic__register_document_impact(
  workspaceId: <id>,
  issueId: <issue ID>,
  documentIds: "<id1>,<id2>",
  reason: "<why these docs need review>"
)
```

### 9c: KnowledgeExtraction discussion entry

Summarize what was captured (or note "nothing captured" if both 9a and 9b were skipped):

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: <summary>,
  entryType: "KnowledgeExtraction"
)
```

Template:

```markdown
## Knowledge Trace — Review

### Toolkit items added
- `KBT-PATN012` — <title> (new)
- `KBT-GTCH008` — <title> (updated)

### Document impacts registered
- `<document name>` — <reason>

### Nothing new to capture
(Use this line when both 9a and 9b were skipped)
```

## Step 10: Final Report

Report:
**"Review + merge + close complete for [ISSUE CODE]. Status: Done.**

**Summary:**
- Verdict: APPROVE
- Merged: `<feature-branch>` → `main` (`<merge commit sha>`)
- Feature branch deleted (local + remote)
- Knowledge: [N] toolkit items, [N] document impacts (or "none")

**Issue closed."**

## Key Principles

- **Specs are the checklist** — review against Kanbantic specifications, not just "does it look good"
- **Categorize issues** — Critical / Important / Minor
- **Create fix tasks on reject** — don't just reject, tell them what to fix
- **Justify rejections** — always provide a clear, detailed reason explaining what failed
- **Push back if wrong** — if reviewer feedback is incorrect, explain why with evidence
- **Merge only after final approve** — no half-merged Epics
- **Done-transitie alleen na merge + push** — never set `Done` on a local-only merge
- **Approval before Done** — every Review→Done transition is preceded by a `ReviewApproval` row via `approve_review` (KBT-F170 / KBT-PR191)
- **Knowledge is optional, not forced** — "nothing to capture" is a valid answer
- **Record everything** — all feedback and decisions go to Kanbantic discussion
