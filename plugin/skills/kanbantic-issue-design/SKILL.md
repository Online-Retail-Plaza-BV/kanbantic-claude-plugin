---
name: kanbantic-issue-design
description: "Use when a new Issue or Feature needs to be designed. Explores requirements through dialogue, then creates the issue with specifications and test cases in Kanbantic. For bugs, use /report-bug instead."
---

# Kanbantic Issue Design

## Overview

Design issues and features through collaborative dialogue. All artifacts are created in Kanbantic via MCP — not in local files. For bugs, use `/report-bug` — it's faster and tailored to bug intake.

**Principle:** Read from Kanbantic → Design with user → Write to Kanbantic.

**Announce at start:** "I'm using the kanbantic-issue-design skill to design this issue."

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY issue regardless of perceived simplicity.
</HARD-GATE>

## Checklist

You MUST complete these steps in order:

1. **Orient** — load workspace context
2. **Explore** — understand existing specifications and conventions
3. **Clarify** — ask questions one at a time
4. **Propose** — present 2-3 approaches with trade-offs
5. **Design** — present design sections, get approval per section
6. **Persist** — create/update issue + specifications + test cases + decision entry in Kanbantic
7. **Handoff** — invoke kanbantic-issue-planning skill

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
4. For **design/planning/review**: stay on the default branch (read-only access)

<IMPORTANT>
- If no repository is configured in the workspace, skip this step and proceed — not all work requires code access.
- If no credential is configured, tell the user: "No repository credential found. Configure a PAT token via Workspace → Repositories → Credentials in the Kanbantic UI."
- If the repo is already cloned but on the wrong branch, run `git checkout main && git pull` to get the latest code.
</IMPORTANT>

## Step 1: Orient

Load workspace context to understand where this issue lives:

```
MCP: mcp__kanbantic__get_context
```

Note the workspace ID, active releases, and applications — you'll need these when creating the issue.

Note the workspace's `TestCoverageEnforcement` and `ReadinessGateEnforcement` settings from the context response. If enforcement is Soft or Hard, ensure your design includes the required artifacts (specifications, test cases) before handoff to planning.

## Step 2: Explore

Read existing requirements, project conventions, and architecture knowledge:

```
MCP: mcp__kanbantic__list_specifications(workspaceId)
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "ClaudeMd")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Pattern")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Gotcha")
MCP: mcp__kanbantic__list_toolkit_items(workspaceId, category: "Rule")
MCP: mcp__kanbantic__list_library_documents(workspaceId, categoryType: "Architecture")
```

Read relevant Library documents for architectural context:
```
MCP: mcp__kanbantic__read_library_document(documentId)  // for relevant architecture docs
```

Only explore the codebase directly (Glob, Grep, Read) for areas not covered by existing Toolkit/Library knowledge.

## Step 3: Clarify

Ask questions **one at a time**, preferring multiple choice:

- Purpose: What problem does this solve?
- Scope: What's in/out?
- Constraints: Performance, compatibility, existing patterns?
- Success criteria: How do we know it works?

Use `AskUserQuestion` with 2-4 options per question. Only one question per message.

## Step 4: Propose Approaches

Present 2-3 approaches with:
- Brief description of each
- Trade-offs (complexity, performance, maintainability)
- Your recommendation with reasoning

Lead with the recommended approach.

## Step 5: Present Design

Present the design in sections scaled to complexity:
- **Data model** (if applicable)
- **Backend logic** (if applicable)
- **Frontend UI** (if applicable)
- **MCP integration** (if applicable)

Ask after each section: "Ziet dit er goed uit?" / "Does this look right?"

Be ready to revise based on feedback.

## Step 6: Persist to Kanbantic

After user approves the complete design:

### 6a: Create or Update Issue

If issue doesn't exist yet:
```
MCP: mcp__kanbantic__create_issue(
  workspaceId: <workspace ID — REQUIRED to ensure correct workspace>,
  releaseId: <active release>,
  type: "Feature" | "Epic",
  title: <title>,
  description: <full design description in Markdown>,
  priority: <priority>,
  applicationId: <if applicable>,
  initiativeId: <if applicable>
)
```

If issue already exists:
```
MCP: mcp__kanbantic__update_issue(issueId, description: <updated description>)
```

### 6b: Create Specifications

Extract requirements from the design. Per requirement:
```
MCP: mcp__kanbantic__create_specification(
  workspaceId: <id>,
  category: "ProductRequirement" | "SystemRequirement" | "Rule" | "Boundary",
  title: <requirement title>,
  content: <requirement in Markdown>
)
```

Categories:
- **ProductRequirement**: User-facing behavior ("Issue detail shows test coverage indicator")
- **SystemRequirement**: Technical constraint ("LEFT JOIN on TestCases for coverage count")
- **SecurityRequirement**: Auth/access rules
- **Rule**: Business logic ("Enforcement Off/Soft/Hard")
- **Boundary**: Scope limits ("No automatic test generation")

### 6c: Create Test Cases

Extract acceptance criteria. Per criterion:
```
MCP: mcp__kanbantic__create_test_case(
  workspaceId: <id>,
  title: <test case title>,
  description: <what to test>,
  steps: <step-by-step>,
  expectedResult: <expected outcome>,
  issueId: <issue ID>,
  priority: "High" | "Medium"
)
```

### 6d: Add Decision Entry

Record the design decision:
```
MCP: mcp__kanbantic__add_discussion_entry(
  issueId: <id>,
  content: <design summary with chosen approach and rationale>,
  entryType: "Decision"
)
```

## Step 7: Handoff

After all artifacts are persisted:

### If Epic:

**"Design complete. Epic [CODE] has been created/updated with [N] specifications and [N] test cases.**

**Next step:** Invoke `kanbantic-issue-planning` to create the implementation plan."

Then invoke: `Skill: kanbantic-issue-planning`

### If Feature:

**"Design complete. Feature [CODE] has been created/updated with [N] specifications and [N] test cases.**

**Next step:** Use `kanbantic-issue-executing` to start implementation. Tasks will be created directly on the issue (Features do not use Implementation Plans with phases)."

Then invoke: `Skill: kanbantic-issue-executing`

## Key Principles

- **One question at a time** — don't overwhelm
- **Multiple choice preferred** — easier for user
- **YAGNI** — remove unnecessary features
- **Kanbantic is source of truth** — all artifacts via MCP, not local files
- **Developer independence** — a developer with only Kanbantic access has everything
