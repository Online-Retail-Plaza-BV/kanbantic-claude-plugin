'use strict';

//
// KBT-F238 — git-sync-check (plugin/hooks/git-sync-check.ps1)
//
// Verifies the four paths covered by KBT-TC1873..KBT-TC1876:
//   - happy path: up-to-date with origin
//   - behind path: rebase via DefaultAction=Pull
//   - skip-env path: KANBANTIC_SKIP_GIT_SYNC=1 opt-out
//   - graceful-degradation paths: no-origin / detached-head / fetch-failed
//
// Strategy: spawn `pwsh` as a child process against real temp git repos
// (one per test) — no MCP, no network. The script emits a single line of
// JSON on stdout that we parse and assert against.
//
// Skipped automatically when pwsh is not on PATH (e.g. CI Linux runners
// without PowerShell installed). The script is PowerShell-Core-compatible
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
  'git-sync-check.ps1'
);

const HAS_PWSH = (() => {
  const r = spawnSync('pwsh', ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'], {
    encoding: 'utf8',
  });
  return r.status === 0;
})();

const HAS_GIT = (() => {
  const r = spawnSync('git', ['--version'], { encoding: 'utf8' });
  return r.status === 0;
})();

const SKIP_REASON = !HAS_PWSH
  ? 'pwsh not on PATH — install PowerShell Core to run these tests'
  : !HAS_GIT
    ? 'git not on PATH — required for the fixture repos'
    : null;

// ---------------------------------------------------------------------------
// fixture helpers
// ---------------------------------------------------------------------------

function git(cwd, args, env) {
  const r = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
    env: Object.assign({}, process.env, env || {}),
  });
  if (r.status !== 0) {
    throw new Error(
      `git ${args.join(' ')} (in ${cwd}) failed with code ${r.status}:\n${r.stderr || r.stdout}`
    );
  }
  return r.stdout.trim();
}

function mkTmpDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function initBareOrigin(originPath) {
  fs.mkdirSync(originPath, { recursive: true });
  git(originPath, ['init', '--bare', '--initial-branch=main']);
}

function initWorkRepo(workPath, originPath) {
  fs.mkdirSync(workPath, { recursive: true });
  git(workPath, ['init', '--initial-branch=main']);
  git(workPath, ['config', 'user.email', 'test@example.com']);
  git(workPath, ['config', 'user.name', 'Test']);
  git(workPath, ['config', 'commit.gpgsign', 'false']);
  if (originPath) {
    git(workPath, ['remote', 'add', 'origin', originPath]);
  }
}

function addCommit(repoPath, fileName, content, message) {
  fs.writeFileSync(path.join(repoPath, fileName), content);
  git(repoPath, ['add', fileName]);
  git(repoPath, ['commit', '-m', message]);
}

function runSyncCheck(repoPath, defaultAction, extraEnv) {
  if (!defaultAction) defaultAction = 'Pull';
  const r = spawnSync(
    'pwsh',
    ['-NoProfile', '-File', SCRIPT_PATH, defaultAction, repoPath],
    {
      encoding: 'utf8',
      env: Object.assign({}, process.env, extraEnv || {}),
      // Make sure the script never inherits a stray opt-out from the host.
      // Caller can re-set it via extraEnv.
    }
  );
  let parsed = null;
  try {
    // The script prints exactly one JSON line. Trim defensive.
    parsed = JSON.parse(r.stdout.trim());
  } catch (e) {
    // Surface parse failure with diagnostic context.
    throw new Error(
      `Could not parse JSON output from sync-check.\nExit: ${r.status}\nStdout:\n${r.stdout}\nStderr:\n${r.stderr}`
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

// Wrap test() so SKIP_REASON is honoured uniformly. node:test treats *any*
// non-undefined `skip` value as "skip" (incl. null/false), so the option must
// be omitted entirely when we actually want the test to run.
function gitTest(name, fn) {
  if (SKIP_REASON) {
    test(name, { skip: SKIP_REASON }, fn);
  } else {
    test(name, fn);
  }
}

// ---------------------------------------------------------------------------
// KBT-TC1873 — happy path: base up-to-date with origin
// ---------------------------------------------------------------------------
gitTest('KBT-TC1873 — sync check up-to-date: behindCount=0, action=up-to-date', (t) => {
  const origin = mkTmpDir('kbt-f238-origin-');
  const work = mkTmpDir('kbt-f238-work-');
  t.after(() => cleanup(origin, work));

  initBareOrigin(origin);
  initWorkRepo(work, origin);
  addCommit(work, 'README.md', '# initial', 'feat: initial');
  git(work, ['push', '-u', 'origin', 'main']);
  // Create a feature branch from main HEAD — no divergence yet.
  git(work, ['checkout', '-b', 'feature/kbt-f238-tc1873']);

  const { exitCode, result } = runSyncCheck(work, 'Pull');
  assert.equal(exitCode, 0);
  assert.equal(result.action, 'up-to-date');
  assert.equal(result.behindCount, 0);
  assert.equal(result.skipped, false);
  assert.equal(result.defaultBranch, 'main');
  assert.equal(result.branch, 'feature/kbt-f238-tc1873');
});

// ---------------------------------------------------------------------------
// KBT-TC1874 — behind path: base is N commits behind origin
// ---------------------------------------------------------------------------
gitTest('KBT-TC1874 — sync check behind: rebases feature-branch + reports behindCount', (t) => {
  const origin = mkTmpDir('kbt-f238-origin-');
  const work = mkTmpDir('kbt-f238-work-');
  const peer = mkTmpDir('kbt-f238-peer-');
  t.after(() => cleanup(origin, work, peer));

  initBareOrigin(origin);
  initWorkRepo(work, origin);
  addCommit(work, 'README.md', '# initial', 'feat: initial');
  git(work, ['push', '-u', 'origin', 'main']);

  // Branch off main at commit A.
  const shaA = git(work, ['rev-parse', 'HEAD']);
  git(work, ['checkout', '-b', 'feature/kbt-f238-tc1874']);
  addCommit(work, 'feature.txt', 'feature work', 'feat: my feature work');

  // Peer clones the bare and pushes commit B onto main, so origin/main moves
  // ahead of our base.
  initWorkRepo(peer, null);
  git(peer, ['remote', 'add', 'origin', origin]);
  git(peer, ['fetch', 'origin']);
  git(peer, ['checkout', '-b', 'main', 'origin/main']);
  addCommit(peer, 'other.txt', 'other change', 'feat: B from peer');
  const shaB = git(peer, ['rev-parse', 'HEAD']);
  git(peer, ['push', 'origin', 'main']);

  // Now back in `work` we are on feature/... — base is 1 commit behind origin.
  const featureSha_before = git(work, ['rev-parse', 'HEAD']);
  const { exitCode, result } = runSyncCheck(work, 'Pull');
  assert.equal(exitCode, 0, `script exit code (stdout=${result && JSON.stringify(result)})`);
  assert.equal(result.action, 'pulled', 'expected action=pulled after default rebase');
  assert.equal(result.behindCount, 1, 'expected behindCount=1');
  assert.equal(result.defaultBranch, 'main');
  // After rebase, our feature-branch should contain commit B.
  const logAfter = git(work, ['log', '--pretty=format:%H', '-n', '5']);
  assert.ok(
    logAfter.includes(shaB),
    `expected feature-branch to contain commit B (${shaB}) after rebase; log:\n${logAfter}`
  );
  // Original A is still in history.
  assert.ok(logAfter.includes(shaA), 'commit A must still be in history');
  // localSha in the result is the post-rebase HEAD.
  assert.notEqual(result.localSha, featureSha_before, 'HEAD must have changed after rebase');
});

// ---------------------------------------------------------------------------
// KBT-TC1875 — opt-out via KANBANTIC_SKIP_GIT_SYNC=1
// ---------------------------------------------------------------------------
gitTest('KBT-TC1875 — sync check opt-out: KANBANTIC_SKIP_GIT_SYNC=1 returns action=skipped-env', (t) => {
  const origin = mkTmpDir('kbt-f238-origin-');
  const work = mkTmpDir('kbt-f238-work-');
  const peer = mkTmpDir('kbt-f238-peer-');
  t.after(() => cleanup(origin, work, peer));

  initBareOrigin(origin);
  initWorkRepo(work, origin);
  addCommit(work, 'README.md', '# initial', 'feat: initial');
  git(work, ['push', '-u', 'origin', 'main']);
  git(work, ['checkout', '-b', 'feature/kbt-f238-tc1875']);
  addCommit(work, 'feature.txt', 'feature work', 'feat: my feature work');

  // Peer pushes commit B → local is behind.
  initWorkRepo(peer, null);
  git(peer, ['remote', 'add', 'origin', origin]);
  git(peer, ['fetch', 'origin']);
  git(peer, ['checkout', '-b', 'main', 'origin/main']);
  addCommit(peer, 'other.txt', 'other change', 'feat: B from peer');
  git(peer, ['push', 'origin', 'main']);

  const featureSha_before = git(work, ['rev-parse', 'HEAD']);
  const { exitCode, result } = runSyncCheck(work, 'Pull', { KANBANTIC_SKIP_GIT_SYNC: '1' });
  assert.equal(exitCode, 0);
  assert.equal(result.action, 'skipped-env');
  assert.equal(result.skipped, true);
  // Feature-branch HEAD must be unchanged (no rebase happened).
  const featureSha_after = git(work, ['rev-parse', 'HEAD']);
  assert.equal(featureSha_after, featureSha_before, 'no rebase must occur under opt-out');
  // Message records the opt-out.
  const joined = (result.messages || []).join('\n');
  assert.ok(/KANBANTIC_SKIP_GIT_SYNC/.test(joined), 'opt-out message must mention env-var');
});

// ---------------------------------------------------------------------------
// KBT-TC1876 — graceful degradation: no-origin / detached-head / fetch-failed
// ---------------------------------------------------------------------------
gitTest('KBT-TC1876 — sync check no-origin: returns action=no-origin without crashing', (t) => {
  const work = mkTmpDir('kbt-f238-work-');
  t.after(() => cleanup(work));
  initWorkRepo(work, null);
  addCommit(work, 'README.md', '# initial', 'feat: initial');
  const { exitCode, result } = runSyncCheck(work, 'Pull');
  assert.equal(exitCode, 0);
  assert.equal(result.action, 'no-origin');
  assert.equal(result.skipped, true);
});

gitTest('KBT-TC1876 — sync check detached-head: returns action=detached-head', (t) => {
  const origin = mkTmpDir('kbt-f238-origin-');
  const work = mkTmpDir('kbt-f238-work-');
  t.after(() => cleanup(origin, work));
  initBareOrigin(origin);
  initWorkRepo(work, origin);
  addCommit(work, 'README.md', '# initial', 'feat: initial');
  git(work, ['push', '-u', 'origin', 'main']);
  // Detach HEAD.
  const sha = git(work, ['rev-parse', 'HEAD']);
  git(work, ['checkout', '--detach', sha]);
  const { exitCode, result } = runSyncCheck(work, 'Pull');
  assert.equal(exitCode, 0);
  assert.equal(result.action, 'detached-head');
  assert.equal(result.skipped, true);
});

gitTest('KBT-TC1876 — sync check fetch-failed: returns action=fetch-failed for unreachable origin', (t) => {
  const work = mkTmpDir('kbt-f238-work-');
  t.after(() => cleanup(work));
  initWorkRepo(work, null);
  addCommit(work, 'README.md', '# initial', 'feat: initial');
  // Add a nonsense origin that cannot be fetched.
  git(work, ['remote', 'add', 'origin', 'file:///does/not/exist/origin']);
  const { exitCode, result } = runSyncCheck(work, 'Pull');
  assert.equal(exitCode, 0);
  assert.equal(result.action, 'fetch-failed');
  assert.equal(result.skipped, true);
});
