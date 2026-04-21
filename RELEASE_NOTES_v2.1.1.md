# Kanbantic Claude Plugin v2.1.1 — Status Gate on kanbantic-issue-review

PATCH release. Adds a missing status HARD-GATE to the review skill so it refuses to run on anything other than `Review` status — aligning it with the gates already present in `triage`, `prepare`, and `execute`.

## Why

During idempotent invocation tests after v2.1.0, it became clear that `/kanbantic-claude-plugin:kanbantic-issue-review` had no `status` gate:

- On a `Done` issue it ran through all steps and produced a no-op — but only after dispatching a reviewer subagent (resource waste) and nearly producing a misleading "Review feedback" discussion entry.
- On `New` / `Triaged` / `InProgress` issues it would try to pull a git diff against a branch that wasn't ready and potentially produce false-approve / false-reject signals.
- `Cancelled` issues got the same treatment.

All other lane skills already had this gate:
- `kanbantic-issue-triage` Step 2 — refuses anything other than `New`
- `kanbantic-issue-execute` Step 1 — refuses anything other than `Triaged` + `isReadyToClaim=true`
- `kanbantic-issue-prepare` Step 1 — refuses anything other than `Triaged`
- **`kanbantic-issue-review`** — had no gate (this release closes the hole)

Tracked in `KBT-B174`.

## What changes

- `plugin/skills/kanbantic-issue-review/SKILL.md` — new **Step 1.5: Status HARD-GATE** between the existing `Step 1: Load Context` and the old Step 2 (now Step 2 Get Git Diff).
- The old Step 1 has been split: `Step 1` now only calls `get_issue(issueId)` (so the gate can run on the real current status), and `Step 1b` loads the rest of the review context (specs, test cases, toolkit items). This keeps the diff / subagent / feedback steps from firing on non-Review issues.
- Gate behavior per status:
  - `Review` → continue silently
  - `New` → stop, redirect to `/triage-issue`
  - `Triaged` → stop, redirect to `/prepare-issue` + `/execute-issue`
  - `InProgress` → stop, redirect to `/execute-issue`
  - `Done` → stop with "already Done; no review needed"
  - `Cancelled` → stop with "was Cancelled; nothing to review"

**No opt-out, no override** — the skill's scope is Review → Done by definition.

## What does NOT change

- The happy path for issues already in `Review` is unchanged. No existing workflow that invokes the review skill correctly sees any new behavior.
- `kanbantic-issue-triage`, `-prepare`, `-execute`, and the intake skills are untouched.
- The worktree HARD-GATE from v2.1.0 stays in place; it continues to run **before** the status gate.

## Migration

Zero user action needed. If you were previously invoking `/kanbantic-claude-plugin:kanbantic-issue-review` on non-Review issues by accident, you'll now see a redirect message instead of a no-op or misleading output.

## Kanbantic tracking

- Bug: `KBT-B174`
- Related follow-up fixes: `KBT-B172` (New → Triaged gate), `KBT-B173` (claim HasAssignee chicken-and-egg). These three together complete the lane-gate consistency for all four lane-verwerkers.
