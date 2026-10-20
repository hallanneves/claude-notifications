// claude-notify-bridge — lets claude-notifications (a macOS notifier for
// Claude Code) land a click on the exact Claude tab or integrated terminal a
// notification came from.
//
// Nothing outside VSCode can address its tabs: AppleScript sees no windows,
// and a vscode:// URL goes to whichever window was active last, where the
// Claude extension would open a SECOND panel resuming a session that is still
// running elsewhere. So each window says who it is, and listens on its own
// socket; the notifier picks the window by process ancestry (a Claude session
// descends from its window's extension host, or from one of its terminals'
// shells) and talks to that window only.
//
// Registry: <bridge dir>/<extension host pid>.json, the bridge dir being
// $NOTIFY_BRIDGE_DIR or ~/Library/Application Support/claude-notifications/vscode.
// Socket: one JSON request line per connection, one JSON line back.
//   {"cmd":"show-terminal","pids":[...]}         focus the terminal whose shell is listed
//   {"cmd":"reveal-session","session":"<uuid>"}  reveal that Claude session's tab
'use strict';

const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const vscode = require('vscode');

const SESSION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_REQUEST = 4096;

function bridgeDir() {
  return process.env.NOTIFY_BRIDGE_DIR
    || path.join(os.homedir(), 'Library', 'Application Support', 'claude-notifications', 'vscode');
}

function activate(context) {
  const dir = bridgeDir();
  const registry = path.join(dir, `${process.pid}.json`);
  // In the per-user temp dir: private, and short, as macOS caps a Unix socket
  // path at 104 bytes.
  const socket = path.join(os.tmpdir(), `claude-notify-${process.pid}.sock`);

  async function publish() {
    const pids = await Promise.all(vscode.window.terminals.map((t) => t.processId));
    const folders = (vscode.workspace.workspaceFolders || []).map((f) => f.uri.fsPath);
    const file = vscode.workspace.workspaceFile;
    const entry = {
      extHostPid: process.pid,
      socket,
      app: vscode.env.appName,
      // What `open -b <editor> <path>` needs to raise THIS window rather than
      // open another: the workspace file, or the only folder.
      openPath: file && file.scheme === 'file' ? file.fsPath : (folders.length === 1 ? folders[0] : ''),
      workspaceFolders: folders,
      terminals: pids.filter((p) => typeof p === 'number'),
    };
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const tmp = `${registry}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(entry), { mode: 0o600 });
    fs.renameSync(tmp, registry);
  }

  async function handle(request) {
    if (request.cmd === 'show-terminal' && Array.isArray(request.pids)) {
      for (const terminal of vscode.window.terminals) {
        if (request.pids.includes(await terminal.processId)) {
          terminal.show(false);
          return { ok: true, did: 'show-terminal' };
        }
      }
      return { ok: false, error: 'terminal not found' };
    }
    if (request.cmd === 'reveal-session' && SESSION_ID.test(String(request.session || ''))) {
      // The Claude extension's own command: reveals the tab (or the side bar)
      // already holding this session.
      await vscode.commands.executeCommand('claude-vscode.primaryEditor.open', request.session);
      return { ok: true, did: 'reveal-session' };
    }
    return { ok: false, error: 'unknown request' };
  }

  const server = net.createServer((conn) => {
    let buffer = '';
    conn.setEncoding('utf8');
    conn.on('error', () => {});
    conn.on('data', (chunk) => {
      buffer += chunk;
      if (buffer.length > MAX_REQUEST) {
        conn.destroy();
        return;
      }
      const end = buffer.indexOf('\n');
      if (end < 0) return;
      let request = {};
      try {
        request = JSON.parse(buffer.slice(0, end));
      } catch (_) {
        // answered as an unknown request below
      }
      handle(request).then(
        (reply) => conn.end(`${JSON.stringify(reply)}\n`),
        (err) => conn.end(`${JSON.stringify({ ok: false, error: String(err) })}\n`),
      );
    });
  });
  server.on('error', () => {});
  try { fs.unlinkSync(socket); } catch (_) { /* first start */ }
  server.listen(socket, () => {
    try { fs.chmodSync(socket, 0o600); } catch (_) { /* best effort */ }
  });

  const republish = () => { publish().catch(() => {}); };
  republish();
  context.subscriptions.push(
    vscode.window.onDidOpenTerminal(republish),
    vscode.window.onDidCloseTerminal(republish),
    vscode.workspace.onDidChangeWorkspaceFolders(republish),
    {
      dispose() {
        server.close();
        for (const file of [registry, socket]) {
          try { fs.unlinkSync(file); } catch (_) { /* already gone */ }
        }
      },
    },
  );
  return { publish, handle };
}

function deactivate() {}

module.exports = { activate, deactivate };
