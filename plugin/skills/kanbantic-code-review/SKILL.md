---
name: kanbantic-code-review
description: "Use after completing an implementation phase or issue. Reviews code against Kanbantic specifications and test cases, then approves or rejects the phase."
---

# Kanbantic Code Review

## Overview

Review completed implementation against Kanbantic specifications and test cases. Dispatch a reviewer subagent, then approve or reject the phase in Kanbantic.

**Principle:** Read specs from Kanbantic → Review code → Write feedback to Kanbantic.

**Announce at start:** "I'm using the kanbantic-code-review skill to review this phase."

## Checklist

1. **Load context** — issue, specifications, test cases
2. **Get diff** — what changed in this phase
3. **Dispatch reviewer** — subagent reviews against specs
4. **Record feedback** — discussion entry with categorized issues
5. **Decide** — approve or reject phase

## Step 1: Load Context

```
MCP: mcp__kanbantic__get_issue(issueId)
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

### If no Critical or Important issues:

```
MCP: mcp__kanbantic__approve_phase(issueId, phaseId)
```

### If Critical or Important issues found:

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

The implementer fixes the issues and re-submits the phase for review.

## Key Principles

- **Specs are the checklist** — review against Kanbantic specifications, not just "does it look good"
- **Categorize issues** — Critical / Important / Minor
- **Create fix tasks** — don't just reject, tell them what to fix
- **Justify rejections** — always provide a clear, detailed reason explaining what failed
- **Push back if wrong** — if reviewer feedback is incorrect, explain why with evidence
- **Record everything** — all feedback goes to Kanbantic discussion
