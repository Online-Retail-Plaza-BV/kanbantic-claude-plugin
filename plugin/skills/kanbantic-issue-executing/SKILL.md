---
name: kanbantic-issue-executing
description: "Use when an implementation plan in Kanbantic needs to be executed. Claims the issue, works through phases and tasks, requests review between phases."
---

# Kanbantic Issue Executing

## Overview

Execute an implementation plan from Kanbantic phase by phase. Each phase gets reviewed before proceeding to the next.

**Principle:** Read plan + knowledge from Kanbantic → Implement code → Update status + knowledge in Kanbantic.

**Announce at start:** "I'm using the kanbantic-issue-executing skill to execute this implementation plan."

## Checklist

1. **Claim issue** — set status to InProgress, record branch
2. **Load plan + knowledge** — get phases, tasks, AND project patterns from Kanbantic
3. **Per phase** — execute tasks, mark for review, get approval
4. **Update knowledge** — store corrections or new discoveries in Toolkit/Library
5. **Complete** — set issue status to Review

## Step 1a: Check Readiness

Before claiming, verify the issue is ready to start:

```
MCP: mcp__kanbantic__get_issue(issueId)
```

Inspect the response:
- **`IsReadyToClaim`**: If `true`, proceed to Step 1b.
- **`IsReadyToClaim`**: If `false`, check `ReadinessChecks` for details:
  - **Hard enforcement**: STOP. Tell the user which checks failed and what needs to be resolved before work can begin. Do not proceed.
  - **Soft enforcement**: Warn the user which checks failed. Ask if they want to override. If yes, collect an `overrideReason` to pass in Step 1b.

## Step 1b: Claim Issue and Create Branch

```
MCP: mcp__kanbantic__claim_issue(issueId, branch: "<branch-name>", overrideReason: "<if soft override>")
```

Branch naming: `feature/<issue-code>-<short-description>` or `fix/<issue-code>-<short-description>`.

Create the branch locally:
```bash
git checkout -b feature/<issue-code>-<description>
```

## Workflow by Issue Type

Not all issues follow the full phase workflow:

- **Bug**: Simplified workflow — NO implementation plan or phases. Skip Step 2a (Load Plan), 3a (Unlock Phase), 3c (Mark Phase for Review), and 3d (Request Code Review per phase). Instead: load tasks directly, execute all fix tasks, then do a single code review at the end before completing.
- **Feature**: Optional plan. If an implementation plan exists, follow the full phase workflow. If no plan exists, load tasks directly and execute them (skip phase-related steps 3a, 3c, 3d).
- **Epic**: Full workflow required — implementation plan with phases, per-phase review, the complete process.

## Step 2: Load Implementation Plan + Project Knowledge

### 2a: Load Plan from Kanbantic

> **Note:** Skip this step for Bugs — bugs use tasks directly without an implementation plan.

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

### 2b: Load Project Knowledge from Kanbantic

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

## Step 3: Execute Per Phase

> **For Bugs:** Skip phase-related steps (3a, 3c, 3d). Execute all tasks in Step 3b, then do a single code review at the end.

For each unlocked phase:

### 3a: Unlock Phase (if needed)

First phase is auto-unlocked. Subsequent phases unlock after the previous is approved:
```
MCP: mcp__kanbantic__unlock_phase(issueId, phaseId)
```

### 3b: Execute Tasks

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

**Commit after each task or logical group:**
```bash
git add <specific files>
git commit -m "feat(<issue-code>): <task description>"
```

### 3c: Mark Phase for Review

After all tasks in the phase are Done:
```
MCP: mcp__kanbantic__mark_phase_for_review(issueId, phaseId)
```

### 3d: Request Code Review

Invoke `kanbantic-code-review` to review the phase:
```
Skill: kanbantic-code-review
```

### 3e: Handle Review Result

- **Approved**: proceed to next phase
- **Rejected**: read rejection reason, fix issues, re-submit for review

## Step 4: Update Knowledge Base

After all phases are implemented (before marking complete), update the project knowledge:

### 4a: Correct Outdated Patterns

If any Toolkit pattern was incorrect or outdated during implementation:
```
MCP: mcp__kanbantic__update_toolkit_item(id, title, content: "<corrected pattern>")
```

### 4b: Add New Discoveries

If you discovered new reusable patterns, gotchas, or rules during implementation:
```
MCP: mcp__kanbantic__create_toolkit_item(
  workspaceId: <id>,
  category: "Pattern" | "Gotcha" | "Rule",
  title: "<descriptive name>",
  content: "<pattern with file paths, code example, when to use>"
)
```

### 4c: Deactivate Obsolete Knowledge

If a pattern no longer applies:
```
MCP: mcp__kanbantic__update_toolkit_item(id, title, content, isActive: false)
```

**Guidelines:**
- Only store patterns reusable across multiple issues
- Include file paths and code examples in every Toolkit item
- Update rather than duplicate — search existing items first
- Skip this step if nothing new was discovered (don't force it)

### 4d: Record Knowledge Traceability

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

## Step 5: Complete Issue

After all phases are approved, check readiness before completing:

```
MCP: mcp__kanbantic__get_issue(issueId)
```

Inspect `IsReadyToClaim` and `ReadinessChecks` again — at completion, these reflect whether all required artifacts (test cases, specifications, etc.) are in place. If checks fail, report the failing checks to the user before proceeding. The user may need to add missing test cases or specifications.

Then update status:
```
MCP: mcp__kanbantic__update_issue_status(issueId, status: "Review")
```

Report:
**"Implementation complete for [ISSUE CODE]. All [N] phases approved. Issue status: Review.**

**Summary:**
- [N] tasks completed
- [N] commits
- Knowledge: [N] Toolkit items created/updated (if any)
- Branch: `feature/<issue-code>-<description>`

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
