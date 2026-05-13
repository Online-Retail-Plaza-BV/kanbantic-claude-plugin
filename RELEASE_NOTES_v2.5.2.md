# Kanbantic Claude Plugin v2.5.2

**Released:** 2026-05-13
**Theme:** Code-review-time routing-mandate enforcement (KBT-B252)

## Summary

Adds an automated routing-mandate pre-check to the **`kanbantic-issue-review`** skill that catches new occurrences of `WebApplicationFactory<Program>` in C# integration-tests before the reviewer subagent runs. Complements the Kanbantic-repo CI grep-backstop (`.github/workflows/routing-mandate-check.yml`) and the workspace Toolkit Rule `KBT-TRUL016`.

The change is purely additive: existing skill behavior, gates, and merge/close flow are unchanged.

## Background — KBT-B252 / KBT-B249

KBT-B249 (v0.7.0) shipped a 404 in production: `/api/health-status` returned `404 Content-Length: 0` because `MapHealthChecks(...)` sat in a bare `app.UseEndpoints(...)` block which ABP's conventional `/api/{controller}` matcher shadowed. The Integration-test `KBT-TC1948` was green via `WebApplicationFactory<Program>` — the test-host didn't replicate ABP's full module-tree-routing volgorde.

KBT-B252 captures the class-of-bug structurally:

- **Toolkit Rule `KBT-TRUL016`** — mandate that new integration-tests use `KanbanticIntegrationTestBase` (or directly extend `AbpAspNetCoreAsyncIntegratedTestBase<TModule>`).
- **Specifications `KBT-RL069`, `KBT-SR322`, `KBT-SR323`** — formalized versions of the same rule + CI + review-skill enforcement.
- **CI grep-backstop** in the Kanbantic repo — fails a PR when the pattern slips through review.
- **This plugin update** — review-time finding so reviewers see it surfaced in feedback, not just on a red CI build.

## What changed in the plugin

### `plugin/skills/kanbantic-issue-review/SKILL.md`

Added **Step 2.5: Automated routing-mandate pre-check** between Step 2 (Get Git Diff) and Step 3 (Dispatch Reviewer Subagent). The step:

1. Runs a deterministic grep on the diff using `git diff --unified=1 ... -- 'test/'` and an awk-block.
2. Detects added lines containing `WebApplicationFactory<Program>` in any `*.IntegrationTests*/*.cs` path.
3. Suppresses hits when the line directly above contains `// approved: <reason >=20 chars>`.
4. When hits are found without suppression: pre-fills an **Important** finding in the reviewer's feedback with the file/line and migration guidance.

### `plugin/skills/kanbantic-issue-review/reviewer-prompt.md`

Extended the **Code Quality** checklist that the reviewer subagent applies, adding an explicit routing-mandate bullet so the reviewer also catches the pattern in addition to the deterministic pre-check.

### `plugin/.claude-plugin/plugin.json`

Version bump `2.5.1 → 2.5.2`. Description updated.

## Compatibility

No breaking changes. Existing review-skill invocations continue to work identically when the diff contains no integration-test changes (the awk-block is a no-op).

## References

- KBT-B252 — class-of-bug Bug
- KBT-B249 — anchor incident
- KBT-RL069, KBT-SR322, KBT-SR323 — specifications
- KBT-TRUL016 — workspace Toolkit Rule
- KBT-TC1976 — review-skill flag-gedrag test case
