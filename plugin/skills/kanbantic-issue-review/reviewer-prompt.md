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

    ## Frozen Test-Policy (Regel E / KBT-F442)
    [PASTE the frozenPolicy table here, with actual Passed counts filled in:]

    | Niveau | Applicabiliteit | Minimum vereist | Passed (werkelijk) | Status |
    |---|---|---|---|---|
    | Unit | Vereist | N | M | ✓ Gedekt / ✗ ONTBREKENDE COVERAGE |
    | Integration | Vereist | N | M | ✓ Gedekt / ✗ ONTBREKENDE COVERAGE |
    | E2E | N.v.t. — [reden] | — | — | ✓ N.v.t. / ✗ Rationale ontbreekt |

    If no test-policy entry was found on the issue: treat all three levels as Vereist/min=1 and flag as Critical.

    ## Project Rules & Patterns (from Kanbantic Toolkit)
    [PASTE relevant Rules, Patterns, and Gotchas from Toolkit.
     The reviewer should verify code adheres to these.]
    - Rule: [title] — [content summary]
    - Pattern: [title] — [content summary]
    - Gotcha: [title] — [content summary]

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
       - Adheres to project Rules, Patterns, and Gotchas from the Toolkit
       - Proper error handling
       - No security vulnerabilities
       - Clean, maintainable code
       - YAGNI — no over-engineering

    4. **Architecture**:
       - Proper separation of concerns
       - Integrates well with existing code
       - No unnecessary coupling

    5. **Test-Policy Coverage Check** (Regel E / KBT-F442):
       - For each level with Applicability `Vereist`: verify `Passed count ≥ Minimum`. If count < minimum → **Critical** issue: "ONTBREKENDE COVERAGE: [level] heeft [M] Passed test cases maar vereist [N]. Voeg [N-M] test case(s) toe en markeer als Passed voor Review."
       - For each level with Applicability `N.v.t.`: verify the rationale is present and ≥20 chars. If missing or too short → **Critical** issue: "N.v.t.-rationale voor [level] ontbreekt of is onvoldoende (<20 chars)."
       - Any test case with status `Failed` or `Blocked` → **Critical** issue.
       - Missing coverage ALWAYS yields REJECT — it cannot be overridden by other strengths.

    6. **Issues**: Categorize as:
       - **Critical**: Must fix (bugs, security, broken functionality, missing test-policy coverage)
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

    ## Test-Policy Coverage (Regel E)
    - [x/blank] Unit: [M] Passed / [N] vereist — [Gedekt / ONTBREKENDE COVERAGE]
    - [x/blank] Integration: [M] Passed / [N] vereist — [Gedekt / ONTBREKENDE COVERAGE]
    - [x/blank] E2E: [M] Passed / [N] vereist — [Gedekt / ONTBREKENDE COVERAGE / N.v.t.: reden]

    ## Verdict
    APPROVE / REJECT (with reason)
    Note: missing coverage on any Vereist level → always REJECT, no exceptions.
    ```
```

## Usage

1. Get specs: `mcp__kanbantic__list_specifications(workspaceId)`
2. Get test cases: `mcp__kanbantic__list_test_cases(workspaceId, issueId)`
3. Get git diff: `git diff <base>..<head>`
4. Fill in template placeholders
5. Dispatch via Agent tool
6. Use result to approve/reject phase in Kanbantic
