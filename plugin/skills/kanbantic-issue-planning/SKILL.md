---
name: kanbantic-issue-planning
description: "Use when an issue needs an implementation plan. Queries knowledge + targeted codebase exploration, creates phases and tasks with full code instructions in Kanbantic."
---

# Kanbantic Issue Planning

## Overview

Create a complete implementation plan in Kanbantic with phases, tasks, and code-level discussion entries. A developer with only Kanbantic access has everything needed to implement.

**Principle:** Read issue + specs + knowledge from Kanbantic → Targeted exploration → Write plan + new knowledge to Kanbantic.

**Announce at start:** "I'm using the kanbantic-issue-planning skill to create the implementation plan."

## Checklist

You MUST complete these steps in order:

1. **Load issue** — get issue context, specs, and test cases
2. **Load knowledge** — query Toolkit patterns + Library docs (avoids redundant codebase exploration)
3. **Targeted exploration** — only explore code areas NOT covered by existing knowledge
4. **Design phases** — group work into logical phases
5. **Create plan** — implementation plan + phases + tasks in Kanbantic
6. **Add code instructions** — discussion entries with full code per phase
7. **Update knowledge** — store newly discovered patterns in Toolkit, update Library if architecture changed
8. **Update status** — issue → Triaged

## Step 1: Load Issue Context

```
MCP: mcp__kanbantic__get_issue(issueId)
MCP: mcp__kanbantic__list_specifications(workspaceId)
MCP: mcp__kanbantic__list_test_cases(workspaceId, issueId)
```

Read the issue description, linked specifications (requirements), and test cases (acceptance criteria). These define WHAT to build.

## Step 2: Load Existing Knowledge

Before exploring the codebase, query the project knowledge base for already-documented patterns and architecture:

```
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Pattern")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Gotcha")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Rule")
MCP: mcp__kanbantic__list_library_documents(workspaceId, categoryType: "Architecture")
```

Read any relevant Library documents (e.g., architecture guides, API patterns, data model docs):
```
MCP: mcp__kanbantic__read_library_document(documentId)
```

This gives you the codebase patterns, known pitfalls, and architecture WITHOUT re-exploring the entire codebase.

## Step 3: Targeted Codebase Exploration

Use Glob, Grep, and Read for **targeted exploration only** — focus on what's NOT already covered by Toolkit/Library knowledge:

- **Known patterns from Toolkit**: Use these directly (file paths, conventions, code structure)
- **New areas**: Only explore code areas relevant to this specific issue that aren't yet documented
- **Verify currency**: Spot-check a few Toolkit patterns against actual code to confirm they're still current
- **Note exact locations**: File paths with line numbers for every change
- **Identify dependencies**: What existing code needs modification vs new files

Be thorough for new areas. Use Toolkit knowledge as-is for established patterns.

## Step 4: Design Phases

Group tasks into logical phases. Each phase is a coherent unit of work:

- **Phase naming**: descriptive, e.g. "Backend Domain Model", "Frontend Issue Detail UI"
- **Phase ordering**: dependencies first (backend before frontend, model before service)
- **Phase size**: 2-5 tasks per phase (small enough for review between phases)

## Step 5: Create Plan in Kanbantic

### 5a: Create Implementation Plan

```
MCP: mcp__kanbantic__create_implementation_plan(
  issueId: <id>,
  title: "<Issue Code> Implementation Plan"
)
```

### 5b: Create Phases

Per phase:
```
MCP: mcp__kanbantic__create_phase(
  issueId: <id>,
  name: "<phase name>",
  description: "<what this phase covers>"
)
```

### 5c: Create Tasks

Per task within a phase:
```
MCP: mcp__kanbantic__add_task(
  issueId: <id>,
  phaseId: <phase ID>,
  title: "<task title>",
  description: "<brief description of what to do>",
  priority: "High" | "Medium" | "Low"
)
```

Task titles should be action-oriented: "Add TestCaseCount fields to IssueDto", "Create test coverage sidebar component".

## Step 6: Add Code Instructions

For each phase, add a KnowledgeExtraction discussion entry with complete code instructions:

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId: <id>,
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

## Step 7: Update Knowledge Base

After exploration and planning, store newly discovered knowledge so future issues benefit:

### 7a: New Patterns → Toolkit

For each significant pattern discovered during exploration that isn't already in the Toolkit:

```
MCP: mcp__kanbantic__create_toolkit_item(
  workspaceId: <id>,
  category: "Pattern",
  title: "<descriptive pattern name>",
  content: "<pattern description with file paths, code example, when to use>"
)
```

**What qualifies as a pattern:**
- Service/component scaffolding patterns (e.g., "ABP AppService with AutoMap", "Angular smart component with reactive state")
- File naming and location conventions
- Common code structures that repeat across features
- Integration patterns (e.g., "MCP tool → AppService → Repository")

### 7b: New Pitfalls → Toolkit

For gotchas discovered during exploration:

```
MCP: mcp__kanbantic__create_toolkit_item(
  workspaceId: <id>,
  category: "Gotcha",
  title: "<pitfall description>",
  content: "<what goes wrong, why, and how to avoid>"
)
```

### 7c: Architecture Changes → Library

If the issue introduces new architectural components (new module, new integration pattern, new layer):

```
MCP: mcp__kanbantic__update_library_document(documentId, content: <updated doc>)
```
Or create a new Architecture document if none exists for this area.

### 7d: Outdated Knowledge → Update

If you discovered that an existing Toolkit item or Library document is outdated:

```
MCP: mcp__kanbantic__update_toolkit_item(id, title, content, isActive: true|false)
```

**Don't over-create:** Only store patterns that are reusable across multiple issues. One-off implementation details belong in task descriptions, not the Toolkit.

### 7e: Record Knowledge Traceability

Add a discussion entry documenting which Toolkit/Library items were consumed and produced:

```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId: <id>,
  content: <knowledge summary>,
  entryType: "KnowledgeExtraction"
)
```

Use this template:

```markdown
## Knowledge Trace — Planning

### Consumed (existing knowledge used for this plan)
- `KBT-PATN001` — ABP AppService pattern (used in Phase 1, 2)
- `KBT-GTCH003` — DI scoping in MCP tools (used in Phase 2)
- Library: "Backend Architecture Overview" (used for service layer design)

### Produced (new knowledge created during this planning)
- `KBT-PATN005` — Angular reactive dashboard pattern (new)
- `KBT-GTCH007` — Virtual scroll requires fixed row height (new)

### Updated
- `KBT-PATN002` — Updated file path from old location to new (corrected)

### No knowledge changes
(Use this line instead if nothing was consumed, produced, or updated)
```

This entry creates traceability between the issue and the knowledge base — visible in the issue's discussion timeline in the Kanbantic UI.

## Step 8: Update Issue Status

```
MCP: mcp__kanbantic__update_issue_status(issueId, status: "Triaged")
```

## Step 9: Optional Git Backup

Optionally save the plan to git as a backup:

```bash
# Save to docs/plans/YYYY-MM-DD-<feature>.md
git add docs/plans/
git commit -m "docs: add implementation plan for <issue code>"
```

## Step 10: Report & Handoff

**"Implementation plan complete for [ISSUE CODE]:**
- **[N] phases** with [N] tasks total
- **[N] discussion entries** with code instructions
- **Knowledge:** [N] new Toolkit items created, [N] updated
- **Status:** Triaged

**Next step:** Use `kanbantic-issue-executing` to start implementation, or assign to a developer in Kanbantic."

## Key Principles

- **Complete code in plan** — don't say "add validation", show the exact code
- **Exact file paths** — always include full path from repo root
- **Line numbers** — specify where changes go
- **Build/test commands** — verify after each step
- **Developer independence** — someone with only Kanbantic needs everything
- **DRY** — don't repeat code across tasks, reference earlier tasks
- **YAGNI** — only what's needed for this issue
