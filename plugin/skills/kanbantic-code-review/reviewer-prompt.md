# Code Reviewer Subagent Prompt Template

Use this template when dispatching a reviewer subagent for a Kanbantic issue phase.

```
Agent tool (superpowers:code-reviewer):
  description: "Review Phase: [phase name] for [issue code]"
  prompt: |
    You are reviewing a completed implementation phase for a Kanbantic issue.

    ## What Was Implemented
    [WHAT_WAS_IMPLEMENTED]

    ## Issue
    Code: [ISSUE_CODE]
    Title: [ISSUE_TITLE]
    Description: [ISSUE_DESCRIPTION]

    ## Requirements (from Kanbantic Specifications)
    [List each specification as a checklist item:]
    - [ ] KBT-PR001: [title] — [content summary]
    - [ ] KBT-SR001: [title] — [content summary]

    ## Test Cases (Acceptance Criteria)
    [List each test case:]
    - [ ] KBT-TC001: [title] — [expected result]
    - [ ] KBT-TC002: [title] — [expected result]

    ## Git Diff
    Base: [BASE_SHA]
    Head: [HEAD_SHA]

    Review the diff between these commits:
    ```bash
    git diff [BASE_SHA]..[HEAD_SHA]
    ```

    ## Your Review

    1. **Requirements Check**: Verify each specification is implemented. Check/uncheck the list.

    2. **Test Case Coverage**: Verify each test case has corresponding implementation.

    3. **Code Quality**:
       - Follows existing codebase patterns
       - Proper error handling
       - No security vulnerabilities
       - Clean, maintainable code
       - YAGNI — no over-engineering

    4. **Architecture**:
       - Proper separation of concerns
       - Integrates well with existing code
       - No unnecessary coupling

    5. **Issues**: Categorize as:
       - **Critical**: Must fix (bugs, security, broken functionality)
       - **Important**: Should fix (missing requirements, poor patterns)
       - **Minor**: Nice to have (style, naming, minor improvements)

    ## Output Format

    ```markdown
    ## Strengths
    - [What was done well]

    ## Issues
    ### Critical
    - [Issue + file:line + fix recommendation]

    ### Important
    - [Issue + recommendation]

    ### Minor
    - [Suggestion]

    ## Requirements Checklist
    - [x/blank] KBT-PR001: ... — [status]

    ## Test Cases
    - [x/blank] KBT-TC001: ... — [status]

    ## Verdict
    APPROVE / REJECT (with reason)
    ```
```

## Usage

1. Get specs: `mcp__kanbantic__list_specifications(workspaceId)`
2. Get test cases: `mcp__kanbantic__list_test_cases(workspaceId, issueId)`
3. Get git diff: `git diff <base>..<head>`
4. Fill in template placeholders
5. Dispatch via Agent tool
6. Use result to approve/reject phase in Kanbantic
