#!/usr/bin/env bats
# A ponte do VSCode (vscode-bridge/): o protocolo da extensao (rodando de
# verdade no Node, com um modulo vscode falso), o pacote .vsix, e o lado do
# shell que escolhe a janela dona da sessao e fala so com ela.

load helpers

setup() {
  common_setup
  copy_skill
  stub_open
  stub_osascript
  # nc falso: grava o pedido e responde FAKE_NC_REPLY.
  cat > "$STUB/nc" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$WORK/nc.args"
cat >> "$WORK/nc.requests"
# Sem \${VAR:-{...}}: no bash 3.2 isso devolve uma chave a mais.
if [ -n "\${FAKE_NC_REPLY:-}" ]; then
  printf '%s\n' "\$FAKE_NC_REPLY"
else
  printf '%s\n' '{"ok":true,"did":"reveal-session"}'
fi
EOF
  chmod +x "$STUB/nc"
  # Antes de restringir o PATH, que deixa o node do Homebrew de fora.
  NODE="$(command -v node || true)"
  restrict_path
  export NOTIFY_BRIDGE_DIR="$WORK/bridge"
  mkdir -p "$NOTIFY_BRIDGE_DIR"
  SESSION_ID="0f4e2c1a-8b7d-4e3f-9a2b-1c3d5e7f9a0b"
}

teardown() { common_teardown; }

# Registro de uma janela viva (o proprio pid do teste faz o papel do
# extension host): registry <arquivo> <extHostPid> <openPath> [pids de terminais]
registry() {
  local terminals="${4:-}"
  jq -n --argjson host "$2" --arg open "$3" --arg sock "$WORK/w$2.sock" --arg t "$terminals" \
    '{extHostPid: $host, socket: $sock, openPath: $open, workspaceFolders: [$open],
      terminals: ($t | split(" ") | map(select(length > 0) | tonumber))}' > "$NOTIFY_BRIDGE_DIR/$1.json"
}

editor_focus() {  # editor_focus <kind> <pids>
  run "$WORK/skill/focus.sh" --cwd /tmp/proj/sub --kind "$1" --host com.microsoft.VSCode \
    --pids "$2" --session "$SESSION_ID" --report "$WORK/report"
}

# ---- lado do shell -------------------------------------------------------------

@test "ponte: painel do Claude revela a aba da sessao na janela dona" {
  registry a $$ /tmp/proj
  editor_focus editor-extension "100 90 $$"
  [ "$status" -eq 0 ]
  # A janela dona sobe pela pasta dela (nunca a subpasta, que abriria outra).
  [ "$(cat "$WORK/open.calls")" = $'-b\ncom.microsoft.VSCode\n/tmp/proj' ]
  [[ "$(cat "$WORK/nc.args")" == *"-U"*"$WORK/w$$.sock"* ]]
  request="$(cat "$WORK/nc.requests")"
  [ "$(echo "$request" | jq -r .cmd)" = "reveal-session" ]
  [ "$(echo "$request" | jq -r .session)" = "$SESSION_ID" ]
  [[ "$(cat "$WORK/report")" == *"editor-reveal-session /tmp/proj"* ]]
}

@test "ponte: terminal integrado mostra o terminal cujo shell e ancestral" {
  registry a $$ /tmp/proj "555 4242"
  export FAKE_NC_REPLY='{"ok":true,"did":"show-terminal"}'
  editor_focus editor-terminal "100 90 4242 70"
  [ "$status" -eq 0 ]
  request="$(cat "$WORK/nc.requests")"
  [ "$(echo "$request" | jq -r .cmd)" = "show-terminal" ]
  [ "$(echo "$request" | jq -c .pids)" = "[100,90,4242,70]" ]
  [[ "$(cat "$WORK/report")" == *"editor-show-terminal"* ]]
}

@test "ponte: janela que nao e dona da sessao nunca e chamada" {
  # Pedir a sessao a janela errada faria a extensao do Claude abrir um
  # SEGUNDO painel retomando uma sessao viva.
  registry outra $$ /tmp/outro-projeto
  editor_focus editor-extension "100 90 80"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/nc.requests" ]
  [ "$(cat "$WORK/open.calls")" = $'-b\ncom.microsoft.VSCode' ]
}

@test "ponte: registro de janela que ja fechou e ignorado" {
  registry morta 999999 /tmp/proj
  editor_focus editor-extension "100 999999"
  [ ! -f "$WORK/nc.requests" ]
}

@test "ponte: resposta de falha cai na janela do projeto" {
  registry a $$ /tmp/proj
  make_ide_lock $$ /tmp/proj
  export FAKE_NC_REPLY='{"ok":false,"error":"terminal not found"}'
  editor_focus editor-terminal "100 $$"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/report")" == *"editor-window com.microsoft.VSCode /tmp/proj"* ]]
}

@test "ponte: sem ponte instalada, cai na janela pela raiz do workspace" {
  make_ide_lock $$ /tmp/proj
  editor_focus editor-extension "100 90"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/nc.requests" ]
  [ "$(cat "$WORK/open.calls")" = $'-b\ncom.microsoft.VSCode\n/tmp/proj' ]
}

@test "ponte: o clique de uma sessao do painel leva ancestrais e sessao" {
  CODE="$(fake_app "Visual Studio Code" com.microsoft.VSCode)"
  fake_ps "100 90 ?? /bin/bash" "90 80 ?? claude" \
    "80 50 ?? ${CODE%%.app/*}.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)" \
    "50 1 ?? $CODE"
  cat > "$STUB/tn" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$WORK/tn.args"
EOF
  chmod +x "$STUB/tn"
  NOTIFY_PID=100 NOTIFY_SESSION="$SESSION_ID" NOTIFY_TARGET_PATH=/tmp/proj NOTIFY_TN="$STUB/tn" \
    run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"'--kind' 'editor-extension'"* ]]
  [[ "$args" == *"'--pids' '100 90 80 50 '"* ]]
  [[ "$args" == *"'--session' '$SESSION_ID'"* ]]
}

# ---- o pacote ------------------------------------------------------------------

@test "vsix: zip com manifesto, content types e a extensao" {
  run "$REPO/vscode-bridge/build-vsix.sh" "$WORK/b.vsix"
  [ "$status" -eq 0 ]
  list="$(unzip -Z1 "$WORK/b.vsix")"
  [[ "$list" == *"[Content_Types].xml"* ]]
  [[ "$list" == *"extension.vsixmanifest"* ]]
  [[ "$list" == *"extension/package.json"* ]]
  [[ "$list" == *"extension/extension.js"* ]]
  manifest="$(unzip -p "$WORK/b.vsix" extension.vsixmanifest)"
  version="$(jq -r .version "$REPO/vscode-bridge/package.json")"
  [[ "$manifest" == *"Id=\"claude-notify-bridge\" Version=\"$version\" Publisher=\"hallanneves\""* ]]
}

# ---- a extensao, de verdade, no Node -------------------------------------------

node_bridge() {  # node_bridge <pedidos em JSON>
  [ -n "$NODE" ] || skip "node ausente"
  mkdir -p "$WORK/node_modules/vscode" "$WORK/tmp"
  cat > "$WORK/node_modules/vscode/index.js" <<'EOF'
const calls = [];
const list = (v) => (v || '').split(',').filter(Boolean);
const event = () => ({ dispose() {} });
module.exports = {
  calls,
  window: {
    terminals: list(process.env.FAKE_TERMINALS).map(Number).map((pid) => ({
      processId: Promise.resolve(pid),
      show(preserveFocus) { calls.push(`show ${pid} ${preserveFocus}`); },
    })),
    onDidOpenTerminal: event,
    onDidCloseTerminal: event,
  },
  workspace: {
    workspaceFolders: list(process.env.FAKE_FOLDERS).map((f) => ({ uri: { fsPath: f } })),
    workspaceFile: process.env.FAKE_WORKSPACE_FILE
      ? { scheme: 'file', fsPath: process.env.FAKE_WORKSPACE_FILE } : undefined,
    onDidChangeWorkspaceFolders: event,
  },
  env: { appName: 'Visual Studio Code' },
  commands: { executeCommand: async (cmd, ...args) => { calls.push(`command ${cmd} ${args.join(' ')}`); } },
};
EOF
  cat > "$WORK/harness.js" <<'EOF'
const fs = require('fs');
const net = require('net');
const path = require('path');
const vscode = require('vscode');
const bridge = require(process.argv[2]);
const requests = JSON.parse(process.argv[3]);
const ask = (socket, raw) => new Promise((resolve) => {
  const conn = net.createConnection(socket);
  let out = '';
  conn.on('data', (d) => { out += d; });
  conn.on('close', () => resolve(out.trim()));
  conn.on('error', () => {});
  conn.write(raw);
});
(async () => {
  const context = { subscriptions: [] };
  const api = bridge.activate(context);
  await api.publish();
  await new Promise((r) => setTimeout(r, 150));
  const file = path.join(process.env.NOTIFY_BRIDGE_DIR, `${process.pid}.json`);
  const registry = JSON.parse(fs.readFileSync(file, 'utf8'));
  const mode = (fs.statSync(registry.socket).mode & 0o777).toString(8);
  const replies = [];
  for (const r of requests) replies.push(await ask(registry.socket, typeof r === 'string' ? r : `${JSON.stringify(r)}\n`));
  context.subscriptions.forEach((s) => s.dispose());
  const cleaned = !fs.existsSync(file) && !fs.existsSync(registry.socket);
  console.log(JSON.stringify({ registry, mode, replies, calls: vscode.calls, cleaned, pid: process.pid }));
  process.exit(0);
})();
EOF
  NODE_PATH="$WORK/node_modules" TMPDIR="$WORK/tmp/" \
    run "$NODE" "$WORK/harness.js" "$REPO/vscode-bridge/extension.js" "$1"
}

@test "extensao: publica quem a janela e, e limpa tudo ao fechar" {
  FAKE_TERMINALS="111,222" FAKE_FOLDERS="/tmp/proj" node_bridge '[]'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c .registry.terminals)" = "[111,222]" ]
  [ "$(echo "$output" | jq -r .registry.openPath)" = "/tmp/proj" ]
  [ "$(echo "$output" | jq -r '.registry.extHostPid == .pid')" = "true" ]
  # Socket so do usuario.
  [ "$(echo "$output" | jq -r .mode)" = "600" ]
  [ "$(echo "$output" | jq -r .cleaned)" = "true" ]
}

@test "extensao: workspace multi-pasta abre pelo arquivo .code-workspace" {
  FAKE_FOLDERS="/a,/b" FAKE_WORKSPACE_FILE="/w/proj.code-workspace" node_bridge '[]'
  [ "$(echo "$output" | jq -r .registry.openPath)" = "/w/proj.code-workspace" ]
}

@test "extensao: show-terminal foca o terminal cujo shell esta nos pids" {
  FAKE_TERMINALS="111,222" node_bridge '[{"cmd":"show-terminal","pids":[9,222,1]},{"cmd":"show-terminal","pids":[9]}]'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.replies[0]' | jq -r .ok)" = "true" ]
  [ "$(echo "$output" | jq -r '.replies[1]' | jq -r .ok)" = "false" ]
  [ "$(echo "$output" | jq -c .calls)" = '["show 222 false"]' ]
}

@test "extensao: reveal-session chama o comando da extensao do Claude" {
  node_bridge "[{\"cmd\":\"reveal-session\",\"session\":\"$SESSION_ID\"}]"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.replies[0]' | jq -r .did)" = "reveal-session" ]
  [ "$(echo "$output" | jq -r '.calls[0]')" = "command claude-vscode.primaryEditor.open $SESSION_ID" ]
}

@test "extensao: id de sessao invalido, lixo e pedido gigante nao executam nada" {
  big="$(printf 'x%.0s' $(seq 1 5000))"
  node_bridge "[{\"cmd\":\"reveal-session\",\"session\":\"../etc; rm -rf\"},\"lixo\\n\",\"$big\"]"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.replies[0]' | jq -r .ok)" = "false" ]
  [ "$(echo "$output" | jq -r '.replies[1]' | jq -r .ok)" = "false" ]
  [ "$(echo "$output" | jq -c .calls)" = "[]" ]
}
