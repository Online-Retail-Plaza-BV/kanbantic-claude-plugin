# Kanbantic Claude Code Plugin — v2.5.0

**Released:** 2026-05-13 · **Issue:** [KBT-F265](https://kanbantic.com/issues/KBT-F265) · **Companion:** [KBT-F264](https://kanbantic.com/issues/KBT-F264) (Kanbantic API change)

## Summary

Adds **`/kanbantic-sync-workspace-skills`** — a new slash-command that materializes the active Kanbantic workspace's `Skill` / `Command` / `Subagent` Toolkit-items as on-disk `.claude/commands/*.md` and `.claude/agents/*.md` files, with manifest-based drift detection. This closes the loop opened by **KBT-TRUL014** ("Toolkit = source-of-truth voor Skill/Command/Subagent; `.claude/`-bestanden zijn afgeleide mirrors"): until v2.5.0, keeping a Toolkit-item and its disk-mirror in sync was a manual, drift-prone copy-paste. After v2.5.0 it is one slash-command.

The companion server-side change **KBT-F264** ships independently via the Kanbantic platform deploy: `bootstrap_agent` now also returns `skills[]`, `commands[]`, `subagents[]`, and `customs[]` arrays so an onboarding agent sees every platform-specific Skill / Command / Subagent from a single MCP call. Together the two features make the Toolkit a fully central source-of-truth for these categories.

## What this adds

### `/kanbantic-sync-workspace-skills` (KBT-F265 / KBT-PR209 / KBT-SR310 / KBT-BD083)

A new SKILL.md plus a pure-Node sync script that the skill orchestrator invokes via stdin pipe.

**Flow:**

1. Agent calls `mcp__kanbantic__get_context` to identify the active workspace (or accepts an explicit `--workspace <slug>`).
2. Agent calls `mcp__kanbantic__list_toolkit_items` three times — once each for categories `Skill`, `Command`, `Subagent`.
3. Concatenated JSON array is piped to `plugin/scripts/sync-workspace-skills.js` on stdin.
4. Script writes/updates/removes files under `.claude/commands/` and `.claude/agents/`, maintains a `.kanbantic-sync.json` manifest, and appends the three mirror-paths to `.gitignore` when missing.

**Slug convention:** title-prefix before the em-dash (`—`, U+2014) → strip leading `/` → lowercase → kebab-case. E.g. `/test-e2e-local — Lokale E2E Test Omgeving` → `test-e2e-local.md`.

**Drift-detection algorithm:** SHA-256 over both `sourceHash` (Toolkit-item `content`) and `targetHash` (full rendered file). Manifest records the last-known hashes per slug. On re-run:

| Manifest | On disk | sourceHash match | Decision |
|---|---|---|---|
| absent | absent | — | **CREATE** |
| absent | present | — | **SKIP** (pre-existing local file; `--force` overwrites) |
| present | absent | — | **RESTORE** |
| present, match | present, match | yes | **UNCHANGED** |
| present, match | present, match | no | **UPDATE** |
| present, match | present, differs | — | **SKIP-LOCAL-EDIT** (warn; `--force` overwrites) |

Deleted/deactivated items: mirror file removed unless locally edited (warn + `--force`).

**Exit codes:** `0` clean, `1` local-edit-warning-preserved or slug-collision, `2` infrastructure failure (not a git repo, malformed JSON, fs error).

**Safety:** Slug collisions are detected BEFORE any disk-write — atomic abort with a structured error listing both offending source-codes. Local edits are preserved by default; user must opt in to `--force`.

### Companion server-side change (deployed separately): KBT-F264

The Kanbantic API's `bootstrap_agent` MCP tool now also includes `skills`, `commands`, `subagents`, and `customs` arrays in its response — additive, backwards-compatible. An onboarding agent that calls only `bootstrap_agent` (per `KBT-CLMD001` instruction) now sees platform-specific Skills + Subagents + Commands without falling back to per-category `list_toolkit_items` calls.

This change is in the Kanbantic monorepo (commit `25f0591` on `main`) and ships via the Kanbantic platform deploy pipeline, NOT this plugin release. The plugin proxy is transparent — it forwards whatever the server registers.

## Files changed

### New
- `plugin/skills/kanbantic-sync-workspace-skills/SKILL.md` (177 LOC) — the slash-command definition.
- `plugin/scripts/sync-workspace-skills.js` (727 LOC) — pure-Node sync engine. CLI + module exports; `runSync()` is the testable entry point.
- `plugin/tests/sync-workspace-skills.test.js` (493 LOC) — 18 new cases covering happy-path, idempotency, update detection, slug collision, isActive=false removal, local-edit warning behaviour, .gitignore management, frontmatter rendering, and full-lifecycle.
- `RELEASE_NOTES_v2.5.0.md` (this file).

### Modified
- `plugin/.claude-plugin/plugin.json` — `version` `2.4.2 → 2.5.0`; `description` extended.

### Not changed
- Proxy code (`plugin/proxy/kanbantic-mcp-proxy.js`) — transparent forwarder, no per-tool allowlist needed.
- Lane-skills (`kanbantic-issue-*`) — `/kanbantic-sync-workspace-skills` is a standalone maintenance utility, NOT part of the lane-flow.
- `known-mcp-tools.json` snapshot — the new skill calls `get_context` + `list_toolkit_items` which were already registered in the snapshot.
- `lint-skills.js` — already validates SKILL.md invariants, automatically picks up the new skill on the next run.

## Verification

```
npm test
```

Result on 2026-05-13 (Windows 11 / Node 24+):

```
ℹ tests 44
ℹ pass 42
ℹ fail 0
ℹ skipped 2  (pre-existing Windows SIGTERM/SIGINT skips per KBT-PATN020)
ℹ duration_ms 40029.8325
```

18 of the 42 passing tests are new in v2.5.0 (KBT-TC1933 through KBT-TC1939 plus their CLI counterparts and a lifecycle integration test). `lint-skills.js` validates the new SKILL.md on every run (all invariants pass).

For an ad-hoc end-to-end check after install:

```bash
# In any Kanbantic-workspace repo with the v2.5.0 plugin loaded:
/kanbantic-sync-workspace-skills
# Expected output:
sync-workspace-skills: created=N updated=0 unchanged=0 deleted=0 warnings=0 forced=0
```

## How to install

```bash
claude plugin install kanbantic-claude-plugin
```

(Re-install picks up the new tag. Existing skills are untouched; you gain `/kanbantic-sync-workspace-skills`.)

## References

- **KBT-F265** — this feature.
- **KBT-F264** — companion server-side change in the Kanbantic monorepo (`bootstrap_agent` arrays).
- **KBT-TRUL014** — the Rule that motivated both features ("Toolkit = source-of-truth").
- **KBT-PR209 / KBT-SR310 / KBT-BD083** — product requirement, system requirement, boundary.
- **KBT-US553** — user story driving this skill.
- **KBT-TC1933 — KBT-TC1939** — test cases.
- **KBT-TRUL013** — Local E2E + no-UI exception (verification stack rationale documented in the issue's proof Comment).
- Sister releases: v2.4.2 (KBT-B192, SKILL.md invariants + lint), v2.4.1 (KBT-B200, drift-detector).
