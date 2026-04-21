# Kanbantic Claude Plugin v2.1.0 — Worktree HARD-GATE

MINOR release. Adds a mechanical safety gate to the three working-tree-mutating lane skills so parallel-agent conflicts on `main` become structurally impossible rather than convention-based.

## Why

Toolkit Rule `KBT-TRUL004` has long prescribed that agents work inside a `git worktree` (not the main clone) to avoid stepping on each other when multiple Claude sessions run concurrently. Enforcement was "reading-based" — the skill reads the Toolkit and is expected to follow. In practice this was inconsistent; during the overnight run of 2026-04-20/21, two agents (this one and Axon 02) worked on `main` at the same time and narrowly avoided a merge collision on the Kanbantic repo.

v2.1.0 makes the rule mechanical.

## What changes

- `kanbantic-issue-execute`, `kanbantic-issue-prepare`, and `kanbantic-issue-review` gain a Step 0.5 `<HARD-GATE>` that compares the output of `git rev-parse --git-dir` with `git rev-parse --git-common-dir`. If both paths are equal, the agent is in the main working tree and the skill stops before any status-mutating or code-changing action.
- The error message is explicit and identical across the three skills:
  ```
  You are in the main working tree (<GIT_COMMON>).
  Run EnterWorktree(name: '<ISSUE-CODE>') first, then re-run this skill.
  See KBT-TRUL004 for the rationale.
  ```
- There is **no opt-out**. This is a working-tree safety check, not an artifact-validation check. Overrides would defeat the purpose in the exact scenarios where the gate matters most (asynchronous parallel sessions).
- `KBT-TRUL004` is updated to document the mechanical enforcement; the rule remains as the rationale reference.

## What does NOT change

Intake and triage skills keep running from the main working tree:

- `kanbantic-bug-report`, `kanbantic-feature-request`, `kanbantic-epic-proposal` — pure MCP intake, no filesystem writes.
- `kanbantic-issue-triage` — go/no-go + metadata only, via MCP.

Blocking these would punish agents who want to quickly capture an idea without first creating a worktree. The filesystem-impact is zero.

## Migration

Agents already working in worktrees per `KBT-TRUL004` notice nothing — the gate passes silently. Agents that were running lane skills from the main clone now see the error and need to run `EnterWorktree(name: '<ISSUE-CODE>')` (or `git worktree add` manually) before retrying.

Humans who consciously edit in the main clone can still do so — just skip the plugin skills and use direct `git` commands. The gate is aimed at the parallel-agent failure mode, not at informed human users.

## Kanbantic tracking

- Initiative: none (standalone plugin follow-up)
- Release: **v0.9.0 — Lane Workflow Skills** (the plugin-v2 release family; v2.1.0 is a follow-up inside it)
- Feature: `KBT-F168`
- Supporting backend fix: `KBT-B172` (shipped in Kanbantic API v0.4.162) — enables `KBT-F168` and every future Feature to pass `New → Triaged` under Hard enforcement without an artifact-bootstrap step
