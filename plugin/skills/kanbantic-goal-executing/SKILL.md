---
name: kanbantic-goal-executing
description: "Use when an implementation plan in Kanbantic needs to be executed. Claims the goal, works through phases and tasks, requests review between phases."
---

# Kanbantic Goal Executing

## Overview

Execute an implementation plan from Kanbantic phase by phase. Each phase gets reviewed before proceeding to the next.

**Principle:** Read plan from Kanbantic → Implement code → Update status in Kanbantic.

**Announce at start:** "I'm using the kanbantic-goal-executing skill to execute this implementation plan."

## Checklist

1. **Claim goal** — set status to InProgress, record branch
2. **Load plan** — get phases and tasks from Kanbantic
3. **Per phase** — execute tasks, mark for review, get approval
4. **Complete** — set goal status to Review

## Step 1: Claim Goal

```
MCP: mcp__kanbantic__claim_goal(goalId, branch: "<branch-name>")
```

Branch naming: `feature/<goal-code>-<short-description>` or `fix/<goal-code>-<short-description>`.

Create the branch locally:
```bash
git checkout -b feature/<goal-code>-<description>
```

## Step 2: Load Implementation Plan

```
MCP: mcp__kanbantic__get_implementation_plan(goalId)
MCP: mcp__kanbantic__list_goal_tasks(goalId)
MCP: mcp__kanbantic__list_discussion_entries(goalId)
```

Read:
- **Phases**: ordered list of work phases
- **Tasks**: per phase, what to implement
- **Discussion entries** (KnowledgeExtraction): code instructions with file paths, snippets, line numbers

The KnowledgeExtraction entries contain the detailed code — use these as your implementation guide.

## Step 3: Execute Per Phase

For each unlocked phase:

### 3a: Unlock Phase (if needed)

First phase is auto-unlocked. Subsequent phases unlock after the previous is approved:
```
MCP: mcp__kanbantic__unlock_phase(goalId, phaseId)
```

### 3b: Execute Tasks

For each task in the phase:

**Start:**
```
MCP: mcp__kanbantic__update_goal_task_status(goalId, taskId, status: "InProgress")
```

**Implement:**
- Read the task description and the KnowledgeExtraction discussion entry for this phase
- Write the code exactly as specified
- Run build/test commands to verify
- Fix any issues

**Complete:**
```
MCP: mcp__kanbantic__update_goal_task_status(goalId, taskId, status: "Done")
MCP: mcp__kanbantic__add_discussion_entry(
  goalId,
  content: "**Task [title] completed.**\n\nChanges:\n- [files changed]\n\nVerification:\n- [build/test results]",
  entryType: "Comment"
)
```

**Commit after each task or logical group:**
```bash
git add <specific files>
git commit -m "feat(<goal-code>): <task description>"
```

### 3c: Mark Phase for Review

After all tasks in the phase are Done:
```
MCP: mcp__kanbantic__mark_phase_for_review(goalId, phaseId)
```

### 3d: Request Code Review

Invoke `kanbantic-code-review` to review the phase:
```
Skill: kanbantic-code-review
```

### 3e: Handle Review Result

- **Approved**: proceed to next phase
- **Rejected**: read rejection reason, fix issues, re-submit for review

## Step 4: Complete Goal

After all phases are approved:
```
MCP: mcp__kanbantic__update_goal_status(goalId, status: "Review")
```

Report:
**"Implementation complete for [GOAL CODE]. All [N] phases approved. Goal status: Review.**

**Summary:**
- [N] tasks completed
- [N] commits
- Branch: `feature/<goal-code>-<description>`

**Next:** Push branch and create PR, or mark as Done if no PR needed."

## Subagent Mode

For large plans, you can dispatch implementer subagents per task. Use the template at `implementer-prompt.md` in this directory.

When using subagents:
1. Dispatch one subagent per task using the Agent tool
2. Review the subagent's output
3. Run code review after each task
4. Update task status in Kanbantic based on results

## Key Principles

- **Follow the plan** — implement exactly what's specified
- **One task at a time** — don't skip ahead
- **Verify before completing** — build and test after each task
- **Commit frequently** — one commit per task or logical unit
- **Update Kanbantic** — status changes and discussion entries for visibility
- **Stop when blocked** — ask questions, don't guess
