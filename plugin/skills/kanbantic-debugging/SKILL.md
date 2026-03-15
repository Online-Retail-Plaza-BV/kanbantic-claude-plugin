---
name: kanbantic-debugging
description: "Use when investigating bugs, test failures, or unexpected behavior for a Kanbantic bug issue. Systematic root cause analysis with results recorded in Kanbantic."
---

# Kanbantic Debugging

## Overview

Systematic debugging for Kanbantic bug issues. Find root cause first, then fix. All findings and fixes are recorded in Kanbantic.

**Principle:** Read bug from Kanbantic → Investigate systematically → Write results to Kanbantic.

**Announce at start:** "I'm using the kanbantic-debugging skill to investigate this bug."

<HARD-GATE>
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.
If you haven't completed Phase 1, you cannot propose fixes.
</HARD-GATE>

## Checklist

1. **Load bug** — get bug details from Kanbantic
2. **Investigate** — systematic root cause analysis (4 phases)
3. **Plan fix** — create tasks in Kanbantic
4. **Fix** — implement and verify
5. **Test** — create regression test case + test run
6. **Document** — root cause analysis in discussion
7. **Complete** — update issue status

## Step 1: Load Bug

```
MCP: mcp__kanbantic__get_issue(issueId)
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Gotcha")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Pattern")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Rule")
```

Load known pitfalls (Gotchas) and established patterns — these may point directly to the root cause or help avoid known traps during investigation.

Read:
- Bug description
- Steps to reproduce
- Expected vs actual behavior
- Priority and context

## Step 2: Investigate — The Four Phases

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read error messages carefully**
   - Stack traces, line numbers, error codes
   - Don't skip warnings

2. **Reproduce consistently**
   - Can you trigger it reliably?
   - What are the exact steps?
   - If not reproducible → gather more data, don't guess

3. **Check recent changes**
   ```bash
   git log --oneline -20
   git diff HEAD~5..HEAD --stat
   ```

4. **Check known gotchas**
   - Review Toolkit Gotchas loaded in Step 1 for any known issues related to the affected area
   - A known gotcha may point directly to the root cause and save investigation time

5. **Trace data flow**
   - Where does the bad value originate?
   - Trace backward through the call stack
   - Fix at source, not at symptom

### Phase 2: Pattern Analysis

1. **Find working examples** — similar working code in the codebase
2. **Compare** — what's different between working and broken?
3. **Identify differences** — list every difference, however small
4. **Understand dependencies** — what components are involved?

### Phase 3: Hypothesis Testing

1. **Form hypothesis**: "I think X is the root cause because Y"
2. **Test minimally**: smallest possible change
3. **One variable at a time**: don't fix multiple things at once
4. **Verify**: if hypothesis wrong, form new one — don't stack fixes

### Phase 4: Implementation

After root cause is confirmed, proceed to fix.

## Step 3: Plan Fix

Create fix tasks in Kanbantic:
```
MCP: mcp__kanbantic__add_task(
  issueId,
  title: "Fix: [specific fix description]",
  description: "[what to change and why]",
  priority: "High"
)
```

## Step 4: Implement Fix

Per fix task:
```
MCP: mcp__kanbantic__update_task_status(issueId, taskId, status: "InProgress")
```

- Implement the fix
- Build and verify
- Run existing tests

```
MCP: mcp__kanbantic__update_task_status(issueId, taskId, status: "Done")
```

Commit:
```bash
git add <files>
git commit -m "fix(<issue-code>): <description>"
```

## Step 5: Create Regression Test

Create a test case that covers this bug:
```
MCP: mcp__kanbantic__create_test_case(
  workspaceId,
  title: "Regression: [bug description]",
  description: "Verifies that [bug] does not recur",
  steps: "[steps to verify the fix]",
  expectedResult: "[expected behavior after fix]",
  issueId,
  priority: "High"
)
```

Record the test run:
```
MCP: mcp__kanbantic__create_test_run(
  workspaceId,
  testCaseId,
  result: "Pass",
  notes: "Verified after fix in commit [sha]"
)
```

## Step 6: Document Root Cause

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId,
  content: <root cause analysis>,
  entryType: "Comment"
)
```

Root cause analysis template:
```markdown
## Root Cause Analysis

**Symptom:** [What was observed]

**Root Cause:** [What actually caused it]

**Investigation:**
1. [Step taken] → [Finding]
2. [Step taken] → [Finding]
3. [Root cause identified]

**Fix:** [What was changed]

**Regression Test:** [Test case code]

**Prevention:** [How to prevent similar issues]
```

## Step 7: Complete

```
MCP: mcp__kanbantic__update_issue_status(issueId, status: "Review")
```

Or if the fix is simple and verified:
```
MCP: mcp__kanbantic__update_issue_status(issueId, status: "Done")
```

## Red Flags — STOP and Return to Phase 1

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "I don't fully understand but this might work"
- "It's probably X, let me fix that"

**STOP. Return to Phase 1.**

If 3+ fixes have failed: question the architecture. Discuss with user before attempting more fixes.

## Key Principles

- **Root cause first** — never fix symptoms
- **One change at a time** — isolate variables
- **Always create regression test** — prevent recurrence
- **Document everything** — future developers need context
- **Kanbantic records all** — investigation and fix in discussion entries
