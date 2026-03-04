---
name: kanbantic-goal-planning
description: "Use when a goal needs an implementation plan. Explores the codebase, creates phases and tasks with full code instructions in Kanbantic."
---

# Kanbantic Goal Planning

## Overview

Create a complete implementation plan in Kanbantic with phases, tasks, and code-level discussion entries. A developer with only Kanbantic access has everything needed to implement.

**Principle:** Read goal + specs from Kanbantic → Explore codebase → Write plan to Kanbantic.

**Announce at start:** "I'm using the kanbantic-goal-planning skill to create the implementation plan."

## Checklist

You MUST complete these steps in order:

1. **Load goal** — get goal context, specs, and test cases
2. **Explore codebase** — find exact file paths, patterns, line numbers
3. **Design phases** — group work into logical phases
4. **Create plan** — implementation plan + phases + tasks in Kanbantic
5. **Add code instructions** — discussion entries with full code per phase
6. **Update status** — goal → Triaged

## Step 1: Load Goal Context

```
MCP: mcp__kanbantic__get_goal(goalId)
MCP: mcp__kanbantic__list_specifications(workspaceId)
MCP: mcp__kanbantic__list_test_cases(workspaceId, goalId)
```

Read the goal description, linked specifications (requirements), and test cases (acceptance criteria). These define WHAT to build.

## Step 2: Explore Codebase

Use Glob, Grep, and Read to understand the codebase:

- **Find relevant files**: Glob for patterns, Grep for keywords
- **Read existing code**: Understand current architecture, patterns, conventions
- **Note exact locations**: File paths with line numbers for every change
- **Identify dependencies**: What existing code needs modification vs new files

Be thorough. The plan must contain enough detail that someone who has never seen the codebase can implement it.

## Step 3: Design Phases

Group tasks into logical phases. Each phase is a coherent unit of work:

- **Phase naming**: descriptive, e.g. "Backend Domain Model", "Frontend Goal Detail UI"
- **Phase ordering**: dependencies first (backend before frontend, model before service)
- **Phase size**: 2-5 tasks per phase (small enough for review between phases)

## Step 4: Create Plan in Kanbantic

### 4a: Create Implementation Plan

```
MCP: mcp__kanbantic__create_implementation_plan(
  goalId: <id>,
  title: "<Goal Code> Implementation Plan"
)
```

### 4b: Create Phases

Per phase:
```
MCP: mcp__kanbantic__create_phase(
  goalId: <id>,
  name: "<phase name>",
  description: "<what this phase covers>"
)
```

### 4c: Create Tasks

Per task within a phase:
```
MCP: mcp__kanbantic__add_goal_task(
  goalId: <id>,
  phaseId: <phase ID>,
  title: "<task title>",
  description: "<brief description of what to do>",
  priority: "High" | "Medium" | "Low"
)
```

Task titles should be action-oriented: "Add TestCaseCount fields to GoalDto", "Create test coverage sidebar component".

## Step 5: Add Code Instructions

For each phase, add a KnowledgeExtraction discussion entry with complete code instructions:

```
MCP: mcp__kanbantic__add_discussion_entry(
  goalId: <id>,
  content: <full code instructions in Markdown>,
  entryType: "KnowledgeExtraction"
)
```

Each entry MUST include:
- **Files to modify/create** with exact paths
- **Code snippets** showing exactly what to add/change
- **Line numbers** where changes go (e.g. "after line 34")
- **Build/test commands** to verify
- **Expected results** after each step

### Code Instruction Template

```markdown
## Phase N: [Phase Name] — Code Instructions

### Task N.1: [Task Title]

**File:** `src/path/to/File.cs`
**Action:** Modify (add after line XX)

// Add these properties after line 34:
public int TestCaseCount { get; set; }
public int TestCasesPassed { get; set; }

**Verify:**
dotnet build

Expected: Build succeeds

### Task N.2: [Task Title]
...
```

## Step 6: Update Goal Status

```
MCP: mcp__kanbantic__update_goal_status(goalId, status: "Triaged")
```

## Step 7: Optional Git Backup

Optionally save the plan to git as a backup:

```bash
# Save to docs/plans/YYYY-MM-DD-<feature>.md
git add docs/plans/
git commit -m "docs: add implementation plan for <goal code>"
```

## Step 8: Report & Handoff

**"Implementation plan complete for [GOAL CODE]:**
- **[N] phases** with [N] tasks total
- **[N] discussion entries** with code instructions
- **Status:** Triaged

**Next step:** Use `kanbantic-goal-executing` to start implementation, or assign to a developer in Kanbantic."

## Key Principles

- **Complete code in plan** — don't say "add validation", show the exact code
- **Exact file paths** — always include full path from repo root
- **Line numbers** — specify where changes go
- **Build/test commands** — verify after each step
- **Developer independence** — someone with only Kanbantic needs everything
- **DRY** — don't repeat code across tasks, reference earlier tasks
- **YAGNI** — only what's needed for this goal
