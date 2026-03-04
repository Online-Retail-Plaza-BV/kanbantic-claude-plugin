# Implementer Subagent Prompt Template

Use this template when dispatching a subagent to implement a single task from a Kanbantic implementation plan.

```
Agent tool (general-purpose):
  description: "Implement Task: [task title]"
  prompt: |
    You are implementing a task from a Kanbantic goal.

    ## Goal
    Code: [GOAL CODE]
    Title: [GOAL TITLE]

    ## Task
    Title: [TASK TITLE]
    Phase: [PHASE NAME]

    ## Code Instructions

    [PASTE the relevant section from the KnowledgeExtraction discussion entry.
     Include: file paths, code snippets, line numbers, build/test commands.]

    ## Context

    [Brief architectural context: what this component does, how it fits,
     what other phases depend on this work.]

    ## Before You Begin

    If anything is unclear — requirements, file locations, approach — ask now.
    Do not guess or make assumptions.

    ## Your Job

    1. Implement exactly what the code instructions specify
    2. Run build/test commands to verify
    3. Commit your work with message: "feat([GOAL CODE]): [task description]"
    4. Self-review (see below)
    5. Report back

    Work from: [repository root directory]

    ## Self-Review Checklist

    Before reporting, verify:
    - [ ] All specified changes implemented
    - [ ] Build succeeds (`dotnet build` / `npm run build`)
    - [ ] Tests pass (`dotnet test` / `npm test`)
    - [ ] No unrelated changes included
    - [ ] Code follows existing codebase patterns
    - [ ] YAGNI — only what was requested

    Fix any issues found before reporting.

    ## Report Format

    When done, report:
    - What you implemented (files changed)
    - Build/test results
    - Self-review findings (if any)
    - Issues or concerns
```

## Usage

When using this template:

1. Get task details from Kanbantic: `mcp__kanbantic__list_goal_tasks(goalId)`
2. Get code instructions from discussion: `mcp__kanbantic__list_discussion_entries(goalId)`
3. Find the KnowledgeExtraction entry matching the current phase
4. Fill in the template placeholders
5. Dispatch via Agent tool with `subagent_type: "general-purpose"`
6. Review the subagent's report
7. Update task status: `mcp__kanbantic__update_goal_task_status(goalId, taskId, status: "Done")`
