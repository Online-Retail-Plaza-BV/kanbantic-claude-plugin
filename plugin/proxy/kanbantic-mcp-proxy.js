#!/usr/bin/env node
'use strict';

//
// kanbantic-mcp-proxy — stdio-to-HTTP bridge for Kanbantic MCP Server
//
// Why this exists:
//   Claude Code's HTTP MCP client has an OAuth-first auth strategy. When the
//   server returns 401, Claude Code enters OAuth discovery mode and caches the
//   result in .credentials.json. Once cached, it never falls back to static
//   Bearer tokens — even after the server removes all OAuth endpoints. This
//   "cache poisoning" causes intermittent auth failures days after install.
//
//   This proxy uses stdio transport (no OAuth, no discovery, no cache) and
//   handles HTTP + Bearer auth itself. Problem permanently eliminated.
//
// Zero dependencies — uses only Node.js built-ins.
//

const https = require('https');
const http = require('http');
const { URL } = require('url');
const { execSync } = require('child_process');

const MCP_URL = process.env.KANBANTIC_MCP_URL || 'https://kanbantic.com/mcp';
let API_KEY = process.env.KANBANTIC_API_KEY;

// Claude Desktop and Cowork launch the proxy as a child of a GUI process that
// inherits its environment from explorer.exe at sign-in. User env vars added
// afterwards are invisible to them until the user signs out and back in. Fall
// back to HKCU\Environment so the key is resolvable without that cycle and
// without requiring a literal secret in claude_desktop_config.json.
if (!API_KEY && process.platform === 'win32') {
  try {
    const out = execSync('reg query HKCU\\Environment /v KANBANTIC_API_KEY', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const m = out.match(/KANBANTIC_API_KEY\s+REG_(?:SZ|EXPAND_SZ)\s+(.+)/i);
    if (m) API_KEY = m[1].trim();
  } catch {
    // Value absent; handled at dispatch time with a clear JSON-RPC error.
  }
}

let sessionId = null;
let stdinEnded = false;

// ---------------------------------------------------------------------------
// stdio: read newline-delimited JSON-RPC from stdin, write to stdout
// Messages are queued and processed sequentially to ensure session state
// (e.g. Mcp-Session-Id from initialize) is available for later requests.
// ---------------------------------------------------------------------------

let buf = '';
const queue = [];
let processing = false;

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buf += chunk;
  drain();
});
process.stdin.on('end', () => {
  stdinEnded = true;
  if (!processing) process.exit(0);
});

function drain() {
  let i;
  while ((i = buf.indexOf('\n')) !== -1) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (line) queue.push(line);
  }
  processQueue();
}

async function processQueue() {
  if (processing) return;
  processing = true;
  while (queue.length > 0) {
    await dispatch(queue.shift());
  }
  processing = false;
  if (stdinEnded) process.exit(0);
}

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

// ---------------------------------------------------------------------------
// dispatch: validate, forward, respond
// ---------------------------------------------------------------------------

async function dispatch(line) {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    process.stderr.write('[kanbantic-proxy] invalid JSON on stdin\n');
    return;
  }

  // Guard: no API key
  if (!API_KEY) {
    process.stderr.write('[kanbantic-proxy] KANBANTIC_API_KEY not set\n');
    if (msg.id != null) {
      send({
        jsonrpc: '2.0',
        error: {
          code: -32603,
          message: 'KANBANTIC_API_KEY not found in environment or Windows User registry. '
            + 'Set it via System Properties → Environment Variables → User variables, '
            + 'then restart the host application.'
        },
        id: msg.id,
      });
    }
    return;
  }

  try {
    const responses = await forward(line);
    for (const r of responses) send(r);
  } catch (err) {
    process.stderr.write(`[kanbantic-proxy] ${err.message}\n`);
    if (msg.id != null) {
      send({
        jsonrpc: '2.0',
        error: { code: -32603, message: err.message },
        id: msg.id,
      });
    }
  }
}

// ---------------------------------------------------------------------------
// forward: POST JSON-RPC to Kanbantic MCP server with Bearer auth
// ---------------------------------------------------------------------------

function forward(body) {
  return new Promise((resolve, reject) => {
    const url = new URL(MCP_URL);
    const transport = url.protocol === 'https:' ? https : http;

    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'Authorization': `Bearer ${API_KEY}`,
    };
    if (sessionId) {
      headers['Mcp-Session-Id'] = sessionId;
    }

    const req = transport.request(
      {
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        method: 'POST',
        headers,
      },
      (res) => {
        // Track session across requests
        if (res.headers['mcp-session-id']) {
          sessionId = res.headers['mcp-session-id'];
        }

        // 202 Accepted — notification acknowledged, no response body
        if (res.statusCode === 202) {
          resolve([]);
          return;
        }

        // 401 — auth failure
        if (res.statusCode === 401) {
          reject(new Error(
            'Authentication failed (401). Verify KANBANTIC_API_KEY is correct.'
          ));
          return;
        }

        // Other errors
        if (res.statusCode < 200 || res.statusCode >= 300) {
          let d = '';
          res.setEncoding('utf8');
          res.on('data', (c) => (d += c));
          res.on('end', () => reject(new Error(`HTTP ${res.statusCode}: ${d}`)));
          return;
        }

        // Success — parse response
        const ct = (res.headers['content-type'] || '').toLowerCase();
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            if (ct.includes('text/event-stream')) {
              resolve(parseSSE(data));
            } else {
              resolve([JSON.parse(data)]);
            }
          } catch (e) {
            reject(new Error(`Failed to parse server response: ${e.message}`));
          }
        });
      },
    );

    req.on('error', (e) => reject(new Error(`Connection failed: ${e.message}`)));
    req.setTimeout(120_000, () => req.destroy(new Error('Request timeout (120s)')));
    req.write(body);
    req.end();
  });
}

// ---------------------------------------------------------------------------
// parseSSE: extract JSON-RPC messages from Server-Sent Events stream
// ---------------------------------------------------------------------------

function parseSSE(data) {
  const messages = [];
  for (const block of data.split('\n\n')) {
    for (const line of block.split('\n')) {
      if (line.startsWith('data:')) {
        const json = line.charAt(5) === ' ' ? line.slice(6) : line.slice(5);
        try {
          messages.push(JSON.parse(json));
        } catch {
          // skip malformed SSE data lines
        }
      }
    }
  }
  return messages;
}
