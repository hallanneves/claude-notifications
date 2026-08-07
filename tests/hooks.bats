#!/usr/bin/env bats
# approval-hook.sh, stop-hook.sh e notify-hook.sh — gate de foreground,
# decisões do dialog, roteamento por notification_type.

load helpers

setup() {
  common_setup
  copy_skill
  stub_notify
  stub_lsappinfo
  stub_osascript
  stub_open
  restrict_path
}

teardown() { common_teardown; }

approval() { "$WORK/skill/approval-hook.sh"; }

# ---- approval-hook -----------------------------------------------------------

@test "approval: editor em primeiro plano suprime o dialog" {
  export FAKE_FRONT="Code"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "approval: NOTIFY_FRONT_APPS extra tambem suprime" {
  export FAKE_FRONT="MeuApp" NOTIFY_FRONT_APPS="MeuApp,Outro"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "approval: ferramentas de interacao nunca geram dialog" {
  export NOTIFY_FORCE=1
  run bash -c 'echo "{\"tool_name\":\"AskUserQuestion\",\"tool_input\":{}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "approval: Aprovar devolve behavior allow com updatedInput" {
  export NOTIFY_FORCE=1 OSA_RESULT="approve"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.behavior')" = "allow" ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.updatedInput.command')" = "ls -la" ]
}

@test "approval: Negar devolve behavior deny" {
  export NOTIFY_FORCE=1 OSA_RESULT="deny"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm x\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.behavior')" = "deny" ]
}

@test "approval: Fechar/Esc nao decide nada" {
  export NOTIFY_FORCE=1 OSA_RESULT="ignore"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "approval: token desconhecido cai no fail-safe" {
  export NOTIFY_FORCE=1 OSA_RESULT="lixo-inesperado"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "approval: timeout descarta token tardio e nunca aprova" {
  # O AppKit pode cuspir um token enquanto o processo morre; o hook precisa
  # ignorar qualquer coisa escrita depois que o watchdog disparou.
  export NOTIFY_FORCE=1 OSA_RESULT="approve" OSA_DELAY=3 NOTIFY_DIALOG_TIMEOUT=1
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "approval: resposta rapida nao espera o timeout inteiro" {
  export NOTIFY_FORCE=1 OSA_RESULT="deny" NOTIFY_DIALOG_TIMEOUT=30
  start="$(date +%s)"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  elapsed=$(( $(date +%s) - start ))
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.behavior')" = "deny" ]
  # O watchdog nao pode segurar o pipe do chamador ate o fim do timeout.
  [ "$elapsed" -lt 10 ]
}

@test "approval: Abrir no editor foca o editor e nao decide" {
  export NOTIFY_FORCE=1 OSA_RESULT="editor"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$(cat "$WORK/open.calls")" == *"com.microsoft.VSCode"* ]]
}

@test "approval: comando longo e truncado com aviso explicito" {
  export NOTIFY_FORCE=1 OSA_RESULT="deny"
  long="$(printf 'a%.0s' $(seq 1 400))"
  run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long\"}}' | \"\$0\"" "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/osascript.calls")" == *"[TRUNCADO"* ]]
}

@test "approval: por padrao o banner NAO carrega o comando (tela de bloqueio)" {
  export NOTIFY_FORCE=1 OSA_RESULT="ignore"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"export TOKEN=segredo123\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  banner="$(cat "$WORK/notify.calls")"
  [[ "$banner" != *segredo123* ]]
  [[ "$banner" == *Bash* ]]
  # O comando continua na janela, que exige sessao desbloqueada.
  [[ "$(cat "$WORK/osascript.calls")" == *segredo123* ]]
}

@test "approval: NOTIFY_BANNER_DETAIL=full devolve o comando ao banner" {
  export NOTIFY_FORCE=1 OSA_RESULT="ignore" NOTIFY_BANNER_DETAIL=full
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"export TOKEN=segredo123\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *segredo123* ]]
}

@test "debug: NOTIFY_DEBUG=1 registra a decisao, e o padrao nao escreve nada" {
  export NOTIFY_FORCE=1 OSA_RESULT="deny"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ ! -f "$WORK/skill/.debug.log" ]

  export NOTIFY_DEBUG=1
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ -f "$WORK/skill/.debug.log" ]
  [[ "$(cat "$WORK/skill/.debug.log")" == *"decision=deny"* ]]
}

@test "approval: dialog recebe o script e o icone do Claude" {
  export NOTIFY_FORCE=1 OSA_RESULT="ignore"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/osascript.calls")"
  [[ "$calls" == *"dialog.js"* ]]
  [[ "$calls" == *"Aprovar:a:approve"* ]]
  [[ "$calls" == *"claude-logo.png"* ]]
}

# ---- stop-hook ---------------------------------------------------------------

@test "stop: suprimido com o editor em primeiro plano" {
  export FAKE_FRONT="Code"
  run bash -c 'echo "{\"cwd\":\"/tmp/meu-projeto\"}" | "$0"' "$WORK/skill/stop-hook.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "stop: notifica --done com o nome do projeto fora do editor" {
  export FAKE_FRONT="Slack"
  run bash -c 'echo "{\"cwd\":\"/tmp/meu-projeto\"}" | "$0"' "$WORK/skill/stop-hook.sh"
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/notify.calls")"
  [[ "$calls" == *--done* ]]
  [[ "$calls" == *meu-projeto* ]]
}

# ---- notify-hook -------------------------------------------------------------

@test "notify-hook: permission_prompt cala quando o approval-hook esta ligado" {
  # Os dois eventos nascem do mesmo pedido: se ambos notificarem, sao dois
  # banners e dois sonares para uma unica permissao.
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"~/.claude/skills/notify/approval-hook.sh"}]}]}}' \
    > "$HOME/.claude/settings.json"
  run bash -c 'echo "{\"notification_type\":\"permission_prompt\",\"message\":\"precisa de permissão\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "notify-hook: permission_prompt notifica quando o approval-hook NAO esta ligado" {
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"outra-coisa.sh"}]}]}}' \
    > "$HOME/.claude/settings.json"
  run bash -c 'echo "{\"notification_type\":\"permission_prompt\",\"message\":\"precisa de permissão\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--approval* ]]
}

@test "notify-hook: permission_prompt vira --approval" {
  run bash -c 'echo "{\"notification_type\":\"permission_prompt\",\"message\":\"Claude precisa de permissão\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--approval* ]]
}

@test "notify-hook: idle_prompt vira banner de espera com Submarine" {
  run bash -c 'echo "{\"notification_type\":\"idle_prompt\",\"message\":\"esperando\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/notify.calls")"
  [[ "$calls" == *"Claude está esperando você"* ]]
  [[ "$calls" == *Submarine* ]]
}

@test "notify-hook: agent_completed vira --done" {
  run bash -c 'echo "{\"notification_type\":\"agent_completed\",\"message\":\"agente terminou\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--done* ]]
}

@test "notify-hook: auth_success e silencioso" {
  run bash -c 'echo "{\"notification_type\":\"auth_success\",\"message\":\"logado\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "notify-hook: sem notification_type cai no fallback por palavra-chave" {
  run bash -c 'echo "{\"message\":\"Claude needs your permission\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--approval* ]]
}
