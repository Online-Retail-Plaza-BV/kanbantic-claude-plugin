# Kanbantic Claude Code Plugin — v2.4.2

**Released:** 2026-05-12 · **Issue:** [KBT-B192](https://kanbantic.com/issues/KBT-B192) · **Spec:** KBT-RL064

## Summary

Bundle-coherence patch release. Fixes lane-skill SKILL.md mechanical inconsistencies that silently misled agents through the lane-flow, and adds a static-lint drift detector wired into `npm test` so the same class of drift cannot regress.

## What this fixes

### F1 / Critical — `update_validation_status` lifecycle hook (KBT-RL064 Invariant 1)

**Symptom:** Linked user stories stayed on `validationStatus = NotImplemented` after their owning issue reached `Done`. Coverage / burndown / initiative-progress metrics treated implemented stories as not-implemented — distorting initiative-scores, dashboards, and release-rapportages.

**Root cause:** No lane-skill instructed the agent to call `update_validation_status` at the canonical lifecycle points. The MCP-tool existed and was documented in the `ai-collaboration` help-page, but the SKILL.md files never bridged the help-page guidance to actionable agent steps.

**Fix:** Two new sub-steps in the lane-skills:

- `kanbantic-issue-execute` Step 7d (renamed old 7d → 7e): after all tasks Done + tests Passed, **before** the Review transition, promote every linked user story `NotImplemented → Implemented`.
- `kanbantic-issue-review` Step 7.5b: after a successful Epic / standalone / Bug final `approve_review` (NOT after Feature-level mini-reviews), promote every linked user story `Implemented → Validated`.

Both calls are guarded against the no-user-story case (silent no-op). Failure is logged as a `Comment` discussion entry and does NOT block the lane transition — best-effort data-integrity.

### C2 / Important — Broken slash-command references in review SKILL.md (KBT-RL064 Invariant 2)

`kanbantic-issue-review/SKILL.md` Step 1.5 instructed users to run `/triage-issue [CODE]`, `/prepare-issue [CODE]`, and `/execute-issue [CODE]`. Per the SKILL frontmatter audit, only `/triage-issue` is a real registered slash-command — the other two resolve to nothing. Agents pointed at those commands hit a dead end.

**Fix:** Replaced all three references with the skill-name form (`kanbantic-issue-triage [CODE]`, `kanbantic-issue-prepare [CODE]`, `kanbantic-issue-execute [CODE]`), which always resolves regardless of whether a `command:` frontmatter exists.

### Drift / Minor — Stale "Review → Done" overview wording (KBT-RL064 Invariant 4)

`kanbantic-issue-review/SKILL.md` line 10 said the skill exits at `Review → Done`. The actual exit since v2.3.0 (KBT-F236 / KBT-RL053) is `Review → InDeployment` — the backend auto-promotes to `Done` only after the deploy-gate clears.

**Fix:** Overview wording corrected: "Complete the Review → InDeployment lane transition (per KBT-RL053; backend auto-promotes to Done on merge or remains InDeployment until deploy-gate clears, KBT-F236)."

## New: static lint-skills drift detector (KBT-RL064 Invariant 3 + AC 4)

`plugin/scripts/lint-skills.js` enforces all four invariants on every `npm test` run. Zero deps (Node built-ins). Exit-code triage mirrors v2.4.1's `check-bundle-tool-drift.js`:

- `0` — all invariants pass.
- `1` — invariant violation (drift detected; stdout names the invariant + file).
- `2` — infrastructure failure (file unreadable, snapshot missing).

The lint complements the v2.4.1 drift detector:

| | Direction | Checks |
|---|---|---|
| **`check-bundle-tool-drift.js`** (v2.4.1) | live MCP registry → MUST-HAVE tools | Are the lane-flow tools (`approve_review` et al.) registered in the live MCP server? |
| **`lint-skills.js`** (v2.4.2) | SKILL.md → canonical snapshot | Is every MCP-tool referenced in a SKILL.md actually in the live registry? Plus invariants 1-2-4 above. |

Canonical snapshot at `plugin/scripts/known-mcp-tools.json` is regenerated whenever the bundle drifts; the `regenerationCommand` field documents how.

## Files changed

### New
- `plugin/scripts/lint-skills.js` (172 LOC).
- `plugin/scripts/known-mcp-tools.json` (156 tools, generated 2026-05-12).
- `plugin/tests/lint-skills.test.js` (118 LOC; 7 cases — 1 positive + 4 negative + 2 infrastructure + 1 sanity).
- `RELEASE_NOTES_v2.4.2.md` (this file).

### Modified
- `plugin/skills/kanbantic-issue-execute/SKILL.md` — new Step 7d (Promote linked user stories to `Implemented`); old 7d renamed 7e.
- `plugin/skills/kanbantic-issue-review/SKILL.md` — overview line 10 corrected; Step 1.5 slash-command refs replaced by skill-name refs; new Step 7.5b (Promote linked user stories to `Validated`).
- `plugin/.claude-plugin/plugin.json` — `version` 2.4.1 → 2.4.2; `description` extended.

## Out-of-scope (explicitly deferred to follow-up issues)

- **G1–G8** — help-page `ai-collaboration` synchronisation. Lives in the Kanbantic API repo (`Kanbantic.HttpApi.Host` library-docs), separate release-train.
- **C1** — frontmatter `command:` symmetry across all 4 lane-skills (subjective).
- **C3** — Tool-whitelist asymmetry between triage and the other lane-skills (subjective).
- **S2–S5** — PO/PD-rolverdeling, library-branch hygiëne, 3-fasen framing, backend Done-gate documentation (subjective rewording).
- **True end-to-end validation-status lane-walk verification** (KBT-TC1698) — needs a lane-walk harness not currently in the plugin repo; kept as Skipped/Manual/E2E for a future integration-test session.
- **Adjacent stale wording in review SKILL.md line 15** ("transitions the issue to Done" without the exact `Review → Done` arrow) — not caught by the lint regex; kept as a known minor inconsistency for a follow-up.

## Verification

```
npm test
```

Result on 2026-05-12 (Windows 11 / Node v24.14.0):

```
✔ drift-detector: positive case — all MUST-HAVE tools present
✔ drift-detector: negative case — approve_review missing → exit 1
✔ positive: real on-disk tree passes all invariants
✔ negative 1 (F1): stripping update_validation_status from execute fails invariant 1
✔ negative 2 (C2): inserting /prepare-issue into review fails invariant 2
✔ negative 3 (drift): unknown mcp__kanbantic__bogus_tool fails invariant 3
✔ negative 4 (state-machine): inserting "Review → Done" into review fails invariant 4
✔ infrastructure: missing snapshot exits 2
✔ infrastructure: malformed snapshot exits 2
✔ sanity: real snapshot includes update_validation_status
✔ proxy forwards approve_review via tools/list + tools/call (real-proxy spawn)
﹣ KBT-TC1865 — proxy graceful shutdown on SIGTERM (skipped — Windows host, see KBT-PATN020)
﹣ KBT-TC1866 — proxy graceful shutdown on SIGINT (skipped — Windows host, see KBT-PATN020)

ℹ tests 13 / pass 11 / fail 0 / skipped 2 / duration_ms 1624
```

## References

- `KBT-B192` — bug.
- `KBT-RL064` — Lane-skill SKILL.md mechanical invariants (this release's spec).
- `KBT-TC1881` — automated lint regression test.
- `KBT-RL053` — Review → InDeployment lane-rule.
- `KBT-F236` — InDeployment status.
- `KBT-TRUL013` — Local E2E + No-UI exception (this release's verification stack).
- `KBT-12-BUG-CAMPAIGN.md` §4.10 — scope-lock authoritative.
- Sister releases: v2.4.1 (KBT-B200, drift-detector infrastructure reused) + v2.3.x (KBT-F236, InDeployment).
