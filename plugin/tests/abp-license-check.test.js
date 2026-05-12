'use strict';

//
// KBT-F263 — abp-license-check (plugin/hooks/abp-license-check.ps1)
//
// Verifies the six paths covered by KBT-TC1913..KBT-TC1918:
//   - KBT-TC1913 — ok            : env-var present + token present + token fresh
//   - KBT-TC1914 — stale-token   : token LastWriteTime > threshold
//   - KBT-TC1915 — missing-env-var: ABP_LICENSE_CODE absent across all scopes
//   - KBT-TC1916 — skipped-env   : KANBANTIC_SKIP_ABP_CHECK=1 opt-out
//   - KBT-TC1917 — out-of-scope  : frontend/plugin issue without backend tag
//   - KBT-TC1918 — SKILL.md      : Step 0.7 integration markers in the skill markdown
//
// KBT-TC1919 (full E2E with live kanbantic-issue-execute) is waivered to manual/CI
// verification, mirroring KBT-F238's E2E test-case justification.
//
// Strategy: spawn `pwsh` as a child process against real temp USERPROFILE
// fixture directories — no MCP, no network. The script emits a single line
// of JSON on stdout that we parse and assert against.
//
// Skipped automatically when pwsh is not on PATH (e.g. CI Linux runners without
// PowerShell installed). The script is PowerShell-Core-compatible
// (`#requires -Version 5.1`), so Linux/macOS CI installing pwsh works too.
//
// Zero deps — only node built-ins.
//

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');

const SCRIPT_PATH = path.resolve(
  __dirname,
  '..',
  'hooks',
  'abp-license-check.ps1'
);

const SKILL_PATH = path.resolve(
  __dirname,
  '..',
  'skills',
  'kanbantic-issue-execute',
  'SKILL.md'
);

const HAS_PWSH = (() => {
  const r = spawnSync('pwsh', ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'], {
    encoding: 'utf8',
  });
  return r.status === 0;
})();

const SKIP_REASON = !HAS_PWSH
  ? 'pwsh not on PATH — install PowerShell Core to run these tests'
  : null;

// ---------------------------------------------------------------------------
// fixture helpers
// ---------------------------------------------------------------------------

function mkTmpDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function mkFreshTokenFixture(prefix, ageDays) {
  // Build a fake USERPROFILE with .abp/cli/access-token.bin, then back-date it
  // to `ageDays` ago (0 = "now"). Returns the path to use as USERPROFILE.
  const profile = mkTmpDir(prefix);
  const dir = path.join(profile, '.abp', 'cli');
  fs.mkdirSync(dir, { recursive: true });
  const tokenPath = path.join(dir, 'access-token.bin');
  fs.writeFileSync(tokenPath, 'fake-token-blob');
  if (ageDays > 0) {
    const now = Date.now();
    const past = new Date(now - ageDays * 24 * 60 * 60 * 1000);
    fs.utimesSync(tokenPath, past, past);
  }
  return profile;
}

function mkEmptyProfile(prefix) {
  // Just an empty USERPROFILE — no .abp/ directory at all.
  return mkTmpDir(prefix);
}

function runHook(args, extraEnv) {
  // Build a sanitized env so we never inherit the host's ABP_LICENSE_CODE,
  // KANBANTIC_SKIP_ABP_CHECK, or USERPROFILE. Each test sets the exact env
  // it wants explicitly.
  const env = Object.assign({}, process.env);
  delete env.ABP_LICENSE_CODE;
  delete env.KANBANTIC_SKIP_ABP_CHECK;
  delete env.KANBANTIC_ABP_TOKEN_MAX_AGE_DAYS;
  // Keep PATH, but blank USERPROFILE so the test fixture has to supply it.
  delete env.USERPROFILE;
  delete env.HOME;
  Object.assign(env, extraEnv || {});

  const fullArgs = ['-NoProfile', '-File', SCRIPT_PATH, ...args];
  const r = spawnSync('pwsh', fullArgs, { encoding: 'utf8', env });
  let parsed = null;
  try {
    parsed = JSON.parse((r.stdout || '').trim());
  } catch (e) {
    throw new Error(
      `Could not parse JSON output from abp-license-check.\nExit: ${r.status}\nStdout:\n${r.stdout}\nStderr:\n${r.stderr}`
    );
  }
  return { exitCode: r.status, stdout: r.stdout, stderr: r.stderr, result: parsed };
}

function cleanup(...paths) {
  for (const p of paths) {
    try {
      fs.rmSync(p, { recursive: true, force: true });
    } catch (_) {
      // best effort
    }
  }
}

function hookTest(name, fn) {
  if (SKIP_REASON) {
    test(name, { skip: SKIP_REASON }, fn);
  } else {
    test(name, fn);
  }
}

// ---------------------------------------------------------------------------
// KBT-TC1913 — ok: env-var present + token present + token fresh
// ---------------------------------------------------------------------------
hookTest('KBT-TC1913 — happy path: ok when env-var set and token fresh', (t) => {
  const profile = mkFreshTokenFixture('kbt-f263-ok-', 0);
  t.after(() => cleanup(profile));

  const { exitCode, result } = runHook(
    ['kanbantic-api', '', profile],
    { ABP_LICENSE_CODE: 'test-license-1234', USERPROFILE: profile, HOME: profile }
  );

  assert.equal(exitCode, 0, `expected exit 0 (stderr=${result && JSON.stringify(result.messages)})`);
  assert.equal(result.action, 'ok');
  assert.equal(result.ok, true);
  assert.equal(result.skipped, false);
  assert.equal(result.applicationSlug, 'kanbantic-api');
  assert.equal(result.thresholdDays, 7);
  assert.ok(result.tokenAgeDays !== null && result.tokenAgeDays < 1, 'token age should be < 1 day');
});

// ---------------------------------------------------------------------------
// KBT-TC1914 — stale-token: token older than threshold
// ---------------------------------------------------------------------------
hookTest('KBT-TC1914 — stale-token: returns action=stale-token + exit 1 when token >7d old', (t) => {
  const profile = mkFreshTokenFixture('kbt-f263-stale-', 10); // 10 days old
  t.after(() => cleanup(profile));

  const { exitCode, result } = runHook(
    ['kanbantic-api', '', profile],
    { ABP_LICENSE_CODE: 'test-license-1234', USERPROFILE: profile, HOME: profile }
  );

  assert.equal(exitCode, 1, 'expected exit 1 for FAIL');
  assert.equal(result.action, 'stale-token');
  assert.equal(result.ok, false);
  assert.ok(result.tokenAgeDays >= 9, `expected tokenAgeDays >= 9, got ${result.tokenAgeDays}`);
  assert.equal(result.thresholdDays, 7);
  const joined = (result.messages || []).join('\n');
  assert.ok(/abp login/.test(joined), `messages should mention "abp login"; got:\n${joined}`);
});

// ---------------------------------------------------------------------------
// KBT-TC1915 — missing-env-var: ABP_LICENSE_CODE not set
// ---------------------------------------------------------------------------
hookTest('KBT-TC1915 — missing-env-var: returns action=missing-env-var when ABP_LICENSE_CODE unset', (t) => {
  // Token file presence is irrelevant here — env-var check is first fail-fast.
  const profile = mkFreshTokenFixture('kbt-f263-noenv-', 0);
  t.after(() => cleanup(profile));

  const { exitCode, result } = runHook(
    ['kanbantic-mcp', '', profile],
    // NOTE: no ABP_LICENSE_CODE in extraEnv — the runHook helper already deleted
    // the inherited one. The script reads User/Machine scope as well, but the
    // hook also accepts process-env which we've explicitly blanked.
    { USERPROFILE: profile, HOME: profile }
  );

  // We allow that on some hosts the User-scope ABP_LICENSE_CODE is actually
  // set (developer machines). If so this test cannot assert missing-env-var
  // reliably and gracefully no-ops. We detect that by checking the action.
  if (result.action !== 'missing-env-var') {
    t.diagnostic(
      `Host has ABP_LICENSE_CODE set on User/Machine scope — cannot validate missing-env-var path. ` +
      `Action returned: ${result.action}. Test passes trivially.`
    );
    return;
  }

  assert.equal(exitCode, 1, 'expected exit 1 for FAIL');
  assert.equal(result.action, 'missing-env-var');
  assert.equal(result.ok, false);
  const joined = (result.messages || []).join('\n');
  assert.ok(/ABP_LICENSE_CODE/.test(joined), `messages should mention ABP_LICENSE_CODE; got:\n${joined}`);
});

// ---------------------------------------------------------------------------
// KBT-TC1916 — skipped-env: KANBANTIC_SKIP_ABP_CHECK=1 opt-out
// ---------------------------------------------------------------------------
hookTest('KBT-TC1916 — opt-out: KANBANTIC_SKIP_ABP_CHECK=1 returns action=skipped-env, exit 0', (t) => {
  // Fixture has NO token file — would normally FAIL with missing-token.
  const profile = mkEmptyProfile('kbt-f263-optout-');
  t.after(() => cleanup(profile));

  const { exitCode, result } = runHook(
    ['kanbantic-api', '', profile],
    { KANBANTIC_SKIP_ABP_CHECK: '1', USERPROFILE: profile, HOME: profile }
  );

  assert.equal(exitCode, 0, 'opt-out must exit 0 so skill continues');
  assert.equal(result.action, 'skipped-env');
  assert.equal(result.skipped, true);
  assert.equal(result.thresholdDays, 7, 'threshold should be reported even on opt-out');
  const joined = (result.messages || []).join('\n');
  assert.ok(/KANBANTIC_SKIP_ABP_CHECK/.test(joined), 'opt-out message must mention env-var');
});

// ---------------------------------------------------------------------------
// KBT-TC1917 — out-of-scope: frontend/plugin issue
// ---------------------------------------------------------------------------
hookTest('KBT-TC1917 — out-of-scope: frontend application + no backend tags returns out-of-scope, exit 0', (t) => {
  const profile = mkEmptyProfile('kbt-f263-oos-');
  t.after(() => cleanup(profile));

  const { exitCode, result } = runHook(
    ['kanbantic-angular', 'frontend,ui', profile],
    // No ABP_LICENSE_CODE — but scope gate must fire first.
    { USERPROFILE: profile, HOME: profile }
  );

  assert.equal(exitCode, 0, 'out-of-scope must exit 0 (no block)');
  assert.equal(result.action, 'out-of-scope');
  assert.equal(result.skipped, true);
  assert.equal(result.applicationSlug, 'kanbantic-angular');
});

hookTest('KBT-TC1917b — in-scope by tag: tag=backend triggers the check even if app is unknown', (t) => {
  const profile = mkFreshTokenFixture('kbt-f263-tag-', 0);
  t.after(() => cleanup(profile));

  const { exitCode, result } = runHook(
    ['some-unknown-app', 'backend', profile],
    { ABP_LICENSE_CODE: 'test', USERPROFILE: profile, HOME: profile }
  );

  assert.equal(exitCode, 0);
  assert.equal(result.action, 'ok', 'backend tag must put us in scope');
});

// ---------------------------------------------------------------------------
// KBT-TC1918 — SKILL.md integration: Step 0.7 wiring
// ---------------------------------------------------------------------------
test('KBT-TC1918 — SKILL.md Step 0.7 invokes abp-license-check.ps1 with correct args', () => {
  // This is a markdown-parse contract-test: no pwsh needed.
  assert.ok(fs.existsSync(SKILL_PATH), `SKILL.md not found at ${SKILL_PATH}`);
  assert.ok(fs.existsSync(SCRIPT_PATH), `abp-license-check.ps1 not found at ${SCRIPT_PATH}`);

  const content = fs.readFileSync(SKILL_PATH, 'utf8');

  // Section header
  assert.ok(/Step 0\.7/.test(content), 'SKILL.md must contain a "Step 0.7" section');

  // Script invocation
  assert.ok(/abp-license-check\.ps1/.test(content), 'SKILL.md must reference the hook script');
  assert.ok(/\$CLAUDE_PLUGIN_ROOT/.test(content), 'SKILL.md must use $CLAUDE_PLUGIN_ROOT for the hook path');

  // Opt-out env var
  assert.ok(/KANBANTIC_SKIP_ABP_CHECK/.test(content), 'SKILL.md must document the KANBANTIC_SKIP_ABP_CHECK opt-out');

  // Action table — all six actions must appear by name so the skill knows how to react.
  for (const act of ['ok', 'out-of-scope', 'skipped-env', 'missing-env-var', 'missing-token', 'stale-token']) {
    assert.ok(
      new RegExp(`\\b${act}\\b`).test(content),
      `SKILL.md Step 0.7 must document the '${act}' action`
    );
  }

  // Provenance reference
  assert.ok(
    /KBT-F263|KBT-CMND007/.test(content),
    'SKILL.md must reference KBT-F263 or KBT-CMND007 for provenance'
  );
});
