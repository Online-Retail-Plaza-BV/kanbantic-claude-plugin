---
name: kanbantic-bug-report
description: "Use when a user wants to report a bug. Lightweight intake: captures what's broken, steps to reproduce, and severity — then creates a Bug goal in Kanbantic."
user_invocable: true
command: report-bug
---

# Kanbantic Bug Report

## Overview

Lightweight bug intake. Capture what's broken, create a Bug goal in Kanbantic. No design phases, no approach comparison — just get the bug documented quickly.

**Principle:** Gather the essentials → Create Bug in Kanbantic → Optionally hand off to debugging or planning.

**Announce at start:** "I'm using the kanbantic-bug-report skill to report this bug."

## Checklist

You MUST complete these steps in order:

1. **Orient** — load workspace context
2. **Gather** — ask what's broken (max 3 questions)
3. **Confirm** — show summary, get approval
4. **Persist** — create Bug goal + optional test case in Kanbantic
5. **Handoff** — suggest next step

## Step 1: Orient

Load workspace context:

```
MCP: mcp__kanbantic__get_context
```

Note the workspace ID, active releases, and applications.

## Step 2: Gather

Ask **at most 3 questions**, one at a time, to fill in the bug details. If the user's initial message already covers some, skip those questions.

The information you need:

| Field | Required | Example |
|-------|----------|---------|
| What's broken | Yes | "Dashboard shows wrong task count" |
| Steps to reproduce | Yes | "1. Open dashboard 2. Look at task count" |
| Expected vs actual | Yes | "Expected: 5 tasks. Actual: shows 0" |
| Severity | No | Critical / High / Medium / Low |
| URL or screenshot | No | "https://kanbantic.com/dashboard" |
| Which application | No | Auto-detect from context if possible |

Use `AskUserQuestion` with options where useful. For severity, offer:
- **Critical** — System down, data loss, no workaround
- **High** — Major feature broken, workaround exists
- **Medium** — Minor feature broken, low impact
- **Low** — Cosmetic, typo, minor inconvenience

If the user doesn't specify severity, default to **Medium**.

## Step 3: Confirm

Present a short summary:

```
**Bug:** [title]
**Severity:** [severity]
**Priority:** [mapped priority]
**Steps to reproduce:**
1. ...
2. ...

**Expected:** ...
**Actual:** ...

Shall I create this bug?
```

Wait for user confirmation before persisting.

## Step 4: Persist to Kanbantic

### 4a: Create Bug Goal

Format the description as structured Markdown with bug details:

```
MCP: mcp__kanbantic__create_goal(
  releaseId: <active release>,
  type: "Bug",
  title: <concise bug title>,
  description: <structured description — see template below>,
  priority: <mapped from severity>,
  applicationId: <if identified>
)
```

Description template:
```markdown
## Steps to Reproduce

1. [step]
2. [step]

## Expected Behavior

[what should happen]

## Actual Behavior

[what actually happens]

## Environment

- URL: [if provided]
- Browser/OS: [if provided]

## Additional Context

[screenshots, error messages, etc.]
```

Priority mapping from severity:
- Critical → Critical
- High → High
- Medium → Medium
- Low → Low

### 4b: Create Regression Test Case (optional)

If the bug is clear enough to define a pass/fail criterion:

```
MCP: mcp__kanbantic__create_test_case(
  workspaceId: <id>,
  title: "Regression: [bug title]",
  description: "Verify that [bug] is fixed",
  steps: "[steps to verify]",
  expectedResult: "[expected behavior after fix]",
  goalId: <bug goal ID>,
  priority: "High"
)
```

Skip this if the bug is vague or needs investigation first.

## Step 5: Handoff

After the bug is created:

**"Bug [CODE] has been created. What would you like to do next?"**

Offer options:
1. **Investigate now** — invoke `kanbantic-debugging` skill
2. **Plan a fix** — invoke `kanbantic-goal-planning` skill (creates implementation plan)
3. **Done for now** — leave it for triage

## Key Principles

- **Fast** — max 3 questions, no design phases
- **Structured** — always include steps to reproduce + expected vs actual
- **Kanbantic is source of truth** — bug details in the goal, not local files
- **Don't over-engineer** — a bug report is not a design document
