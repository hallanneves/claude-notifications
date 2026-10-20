#!/usr/bin/env bats
# O plugin: manifestos, hooks/hooks.json, a espera enquanto a instalacao
# antiga (pre-2.0) ainda esta ligada, e o hook de SessionStart.

load helpers

# O CLI de verdade, achado antes de os stubs tomarem o PATH; so para validar.
REAL_CLAUDE="$(command -v claude 2>/dev/null || true)"

setup() {
  common_setup
  copy_repo
  # Sem o terminal-notifier da maquina: com ele, "falta o app" pediria setup.
  restrict_path
  stub_lsappinfo
  stub_osascript
  SKILL="$WORK/repo/skills/notify"
  # Os hooks rodam a partir da copia do plugin, como o Claude Code os chama.
  export CLAUDE_PLUGIN_ROOT="$WORK/repo"
}

teardown() { common_teardown; }

# notify.sh vira gravador: argv em $WORK/notify.calls.
record_notify() {
  cat > "$SKILL/notify.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "$WORK/notify.calls"
EOF
  chmod +x "$SKILL/notify.sh"
}

# setup.sh vira gravador: so registra que rodou.
record_setup() {
  cat > "$SKILL/setup.sh" <<EOF
#!/bin/bash
echo ran >> "$WORK/setup.calls"
EOF
  chmod +x "$SKILL/setup.sh"
}

session_start() { echo '{"source":"startup"}' | "$SKILL/session-hook.sh"; }

@test "plugin: versao do plugin.json e a do VERSION" {
  [ "$(jq -r .version "$REPO/.claude-plugin/plugin.json")" = "$(cat "$REPO/VERSION")" ]
}

@test "plugin: o marketplace lista este plugin, na raiz, com os nomes que os scripts usam" {
  names="$(bash -c '. "$1/skills/notify/notify-lib.sh"; printf "%s %s" "$PLUGIN_NAME" "$MARKETPLACE_NAME"' _ "$REPO")"
  [ "$names" = "$(jq -r .name "$REPO/.claude-plugin/plugin.json") $(jq -r .name "$REPO/.claude-plugin/marketplace.json")" ]
  [ "$(jq -r '.plugins[0].name' "$REPO/.claude-plugin/marketplace.json")" = "$(jq -r .name "$REPO/.claude-plugin/plugin.json")" ]
  [ "$(jq -r '.plugins[0].source' "$REPO/.claude-plugin/marketplace.json")" = "." ]
}

@test "plugin: todo hook do hooks.json aponta para um script executavel" {
  cmds="$(jq -r '.hooks[][].hooks[].command' "$REPO/hooks/hooks.json")"
  [ "$(printf '%s\n' "$cmds" | wc -l | tr -d ' ')" = "5" ]
  while IFS= read -r cmd; do
    path="$(printf '%s' "$cmd" | tr -d '"')"
    path="${path/\$\{CLAUDE_PLUGIN_ROOT\}/$REPO}"
    [ -x "$path" ] || { echo "nao executavel: $cmd"; return 1; }
  done <<< "$cmds"
}

@test "plugin: so a aprovacao segura a sessao; o resto roda em segundo plano" {
  h="$REPO/hooks/hooks.json"
  [ "$(jq '.hooks.PermissionRequest[0].hooks[0].timeout' "$h")" = "90" ]
  for ev in Notification Stop UserPromptSubmit; do
    [ "$(jq --arg ev "$ev" '.hooks[$ev][0].hooks[0].async' "$h")" = "true" ] || { echo "$ev"; return 1; }
  done
  [ "$(jq -r '.hooks.SessionStart[0].matcher' "$h")" = "startup|resume" ]
}

@test "plugin: o manifesto passa no claude plugin validate" {
  # Sem o CLI (o job de testes do CI), quem valida e o job "plugin".
  [ -n "$REAL_CLAUDE" ] || skip "claude nao instalado"
  run "$REAL_CLAUDE" plugin validate "$REPO"
  [ "$status" -eq 0 ]
}

@test "plugin: com a instalacao antiga ligada, os hooks do plugin nao fazem nada" {
  make_legacy_install
  record_notify
  run bash -c 'echo "{\"session_id\":\"s1\",\"cwd\":\"/tmp/p\"}" | NOTIFY_FORCE=1 "$0"' "$SKILL/stop-hook.sh"
  [ "$status" -eq 0 ]
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$SKILL/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c 'echo "{\"notification_type\":\"idle_prompt\",\"message\":\"x\"}" | "$0"' "$SKILL/notify-hook.sh"
  [ ! -f "$WORK/notify.calls" ]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "plugin: a instalacao antiga, rodando os proprios hooks, segue notificando" {
  make_legacy_install
  record_notify
  # Sem CLAUDE_PLUGIN_ROOT: e o hook vindo do settings.json.
  run bash -c 'echo "{\"session_id\":\"s1\",\"cwd\":\"/tmp/p\"}" | env -u CLAUDE_PLUGIN_ROOT NOTIFY_FORCE=1 "$0"' "$SKILL/stop-hook.sh"
  [ "$status" -eq 0 ]
  [ -f "$WORK/notify.calls" ]
}

@test "plugin: sem instalacao antiga, o hook do plugin notifica" {
  record_notify
  run bash -c 'echo "{\"session_id\":\"s1\",\"cwd\":\"/tmp/p\"}" | NOTIFY_FORCE=1 "$0"' "$SKILL/stop-hook.sh"
  [ "$status" -eq 0 ]
  [ -f "$WORK/notify.calls" ]
}

@test "plugin: regra de permissao com o caminho antigo nao conta como instalacao antiga" {
  mkdir -p "$HOME/.claude"
  echo '{"permissions":{"allow":["Bash(bash ~/.claude/skills/notify/notify.sh:*)"]}}' > "$HOME/.claude/settings.json"
  record_notify
  run bash -c 'echo "{\"session_id\":\"s1\",\"cwd\":\"/tmp/p\"}" | NOTIFY_FORCE=1 "$0"' "$SKILL/stop-hook.sh"
  [ -f "$WORK/notify.calls" ]
}

@test "sessao: com a instalacao antiga ligada, pede /notify migrate e nao prepara nada" {
  make_legacy_install
  record_setup
  run session_start
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq -r .systemMessage)" == *"/notify migrate"* ]]
  [ ! -f "$WORK/setup.calls" ]
}

@test "sessao: a primeira sessao de uma versao prepara em segundo plano, a seguinte nao" {
  record_setup
  run session_start
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq -r .systemMessage)" == *"$(cat "$REPO/VERSION")"* ]]
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$WORK/setup.calls" ] && break; sleep 0.2; done
  [ "$(cat "$WORK/setup.calls")" = "ran" ]
  # O setup de verdade grava a versao; aqui o gravador nao, entao gravamos.
  cp "$REPO/VERSION" "$STATE/.setup-version"
  run session_start
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  sleep 0.3
  [ "$(wc -l < "$WORK/setup.calls" | tr -d ' ')" = "1" ]
}

@test "sessao: atualizacao automatica desligada vira um aviso, uma vez so" {
  mkdir -p "$STATE" "$HOME/.claude/plugins"
  cp "$REPO/VERSION" "$STATE/.setup-version"
  echo '{"claude-notifications":{"source":{"source":"github","repo":"hallanneves/claude-notifications"}}}' \
    > "$HOME/.claude/plugins/known_marketplaces.json"
  run session_start
  [[ "$(echo "$output" | jq -r .systemMessage)" == *"Enable auto-update"* ]]
  run session_start
  [ -z "$output" ]
}

@test "sessao: sem aviso de atualizacao com auto-update ligado ou checkout local" {
  mkdir -p "$STATE" "$HOME/.claude/plugins"
  cp "$REPO/VERSION" "$STATE/.setup-version"
  echo '{"claude-notifications":{"source":{"source":"github","repo":"x/y"},"autoUpdate":true}}' \
    > "$HOME/.claude/plugins/known_marketplaces.json"
  run session_start
  [ -z "$output" ]
  echo '{"claude-notifications":{"source":{"source":"directory","path":"/tmp/x"}}}' \
    > "$HOME/.claude/plugins/known_marketplaces.json"
  run session_start
  [ -z "$output" ]
}

@test "conf: o notify.conf da instalacao antiga vale ate a migracao" {
  mkdir -p "$HOME/.claude/skills/notify"
  echo 'NOTIFY_LANG="en"' > "$HOME/.claude/skills/notify/notify.conf"
  run bash -c 'unset NOTIFY_LANG; . "$1/notify-lib.sh"; load_notify_conf; printf "%s" "$NOTIFY_LANG_RESOLVED"' _ "$SKILL"
  [ "$output" = "en" ]
  # O do diretorio de estado vence.
  mkdir -p "$STATE"
  echo 'NOTIFY_LANG="pt"' > "$STATE/notify.conf"
  run bash -c 'unset NOTIFY_LANG; . "$1/notify-lib.sh"; load_notify_conf; printf "%s" "$NOTIFY_LANG_RESOLVED"' _ "$SKILL"
  [ "$output" = "pt" ]
}
