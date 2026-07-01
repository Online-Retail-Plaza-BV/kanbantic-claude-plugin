# Release Notes — v2.10.0 (KBT-F464)

## `filePath` parameter for large content in the stdio proxy

v2.10.0 lets a `tools/call` carry a local **`filePath`** instead of a large
`content` string. The `kanbantic-mcp-proxy` runs locally with filesystem
access, so it reads the file and substitutes its contents into `content`
before forwarding to the Kanbantic MCP server — the model never has to load the
file into its context.

The motivating case: `add_wireframe_version` takes a `content` string that for a
real wireframe is easily 150KB+ of HTML. Passing that inline overflows the
context window and the upload fails in practice. With `filePath`, Claude only
names the path.

### Behavior

| Arguments | Proxy behavior |
|---|---|
| `content` only | forwarded byte-identical — unchanged from before |
| `filePath` (no `content`) | file read via `fs.readFileSync(filePath, 'utf8')` → `content` filled, `filePath` removed, then forwarded |
| `filePath` **and** non-empty `content` | JSON-RPC error **-32602** (ambiguity) — **not** forwarded; supply exactly one |
| `filePath` unreadable / missing | JSON-RPC error **-32603** naming the path + OS reason (e.g. `ENOENT`) — **not** forwarded; the proxy does not crash |
| neither | forwarded unchanged; the server validates its own required fields |

Substitution happens in `dispatch()` before `forward()`: on a mutation the
re-serialized message is forwarded; otherwise the original line is forwarded
verbatim (preserving byte-identical passthrough).

### Generic, not hardcoded (KBT-RL134)

- **Request-side:** the `filePath → content` substitution applies to *any*
  `tools/call` with a non-empty `filePath`, regardless of tool name. No tool
  allowlist — the server validates whether the tool accepts a `content` field.
- **Response-side (`tools/list` augmentation):** the proxy enriches the
  `tools/list` response so every tool whose `inputSchema` has a `content`
  property also advertises an optional `filePath` string parameter (with a
  description), and notes it in the tool description. `filePath` is never added
  to `required`; tools without `content` are untouched. This is how the
  proxy surfaces a documented parameter even though tool schemas are served by
  the remote server (which the plugin cannot change server-side).

A future content-bearing tool gains `filePath` support automatically — no proxy
code change.

### Trust boundary

`filePath` lets a tool call read any local file the proxy process can access and
sends its contents to the server. That is the intended capability (the proxy
runs locally with filesystem rights), but it means a mistaken or hostile call
could read sensitive files. The proxy intentionally imposes no path allowlist or
size cap — that remains the caller's responsibility. Compare the server-side
`AddIssueAttachment` (KBT-SR224), which does cap at 25MB because it base64-encodes
the payload into the protocol; the proxy substitution has no such overhead. An
optional size guard in the proxy is a reasonable follow-up. Documented in the
plugin README.

### Implementation

- `plugin/proxy/kanbantic-mcp-proxy.js` — `resolveFilePathArgument()` (request)
  and `augmentToolsListResponse()` (response); both property-driven. Runtime
  startup (stdin + SIGINT/SIGTERM handlers) moved behind a
  `require.main === module` guard, and the pure helpers are exported so unit
  tests can `require()` the module without runtime side effects. The internal
  proxy paths (Agent Communication Hub inbox-poll, override-governance flag,
  graceful-exit) call `forward()` directly and bypass the substitution — those
  paths are unaffected.
- Zero new dependencies (Node built-ins only).

### Test coverage

`plugin/tests/proxy-filepath.test.js` — 9 tests:
- Unit (require the module): happy-path substitution, content-only/neither
  passthrough, ambiguity (-32602), missing file (-32603 with path + ENOENT),
  `augmentToolsListResponse` (optional `filePath`, not in `required`,
  non-content tool untouched, idempotent, tolerant of malformed responses).
- Integration / E2E (real proxy spawned against a stub backend): filePath read
  end-to-end (backend receives `content`, never `filePath`); `tools/list`
  augmentation; ambiguity error round-trips and is not forwarded.

Full suite: **100 passed, 0 failed, 4 skipped** (the 4 skips are pre-existing
and unrelated — 2 require a live sandbox, 2 are Windows SIGTERM/SIGINT signal
tests covered via Docker per KBT-B195).

## Also in this release

This version number also captures **KBT-F465** — the new `kanbantic-bug-autopilot`
skill (`/bug-autopilot`) — which merged to `main` without its own version bump.
It processes one or more Kanbantic bug issues fully autonomously from their
current status to Done, handling batches sequentially by priority, fetching the
live workflow at runtime, and reporting per-bug results and a token breakdown by
model.

### Target

- Issue: KBT-F464 (this release's headline); also includes KBT-F465
- Application: Kanbantic Claude Code Plugin
- Merged to main: 9076b21
- Review: ApprovedWithComments (independent reviewer subagent)
