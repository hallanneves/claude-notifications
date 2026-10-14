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

@test "approval: Ir para a sessao foca o app da sessao e nao decide" {
  export NOTIFY_FORCE=1 OSA_RESULT="editor" __CFBundleIdentifier="com.microsoft.VSCode"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$(cat "$WORK/open.calls")" == *"com.microsoft.VSCode"* ]]
}

@test "approval: comando longo vai inteiro para a janela, sem truncar" {
  export NOTIFY_FORCE=1 OSA_RESULT="deny"
  long="$(printf 'a%.0s' $(seq 1 400))"
  run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long\"}}' | \"\$0\"" "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/osascript.calls")" == *"$long"* ]]
  [[ "$(cat "$WORK/osascript.calls")" != *"TRUNCADO"* ]]
}

@test "approval: a janela mostra o comando exato, sem trocar aspas nem barras" {
  # Quem aprova tem que ler byte a byte o que vai rodar.
  export NOTIFY_FORCE=1 OSA_RESULT="ignore"
  run bash -c 'jq -cn --arg c "printf \"%s\\n\" C:\\dir" "{tool_name:\"Bash\",tool_input:{command:\$c}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  grep -qxF 'printf "%s\n" C:\dir' "$WORK/osascript.calls"
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
  # Aprovar nao tem atalho: so um clique aprova, nunca uma tecla perdida.
  [[ "$calls" == *"Aprovar::approve|Negar:n:deny"* ]]
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

@test "notify-hook: permission_prompt avisa quando o dialogo nao apareceu" {
  # Com o editor na frente o approval-hook nao abre nada; se o Notification
  # tambem calasse, a permissao ficaria sem aviso nenhum.
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"~/.claude/skills/notify/approval-hook.sh"}]}]}}' \
    > "$HOME/.claude/settings.json"
  run bash -c 'echo "{\"session_id\":\"s1\",\"notification_type\":\"permission_prompt\",\"message\":\"precisa de permissão\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--approval* ]]
}

@test "notify-hook: permission_prompt cala quando o dialogo ja avisou esta sessao" {
  # O mesmo pedido dispara os dois eventos: um banner e um sonar so.
  export NOTIFY_FORCE=1 OSA_RESULT="ignore"
  run bash -c 'echo "{\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  run bash -c 'echo "{\"session_id\":\"s1\",\"notification_type\":\"permission_prompt\",\"message\":\"precisa de permissão\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--approval' "$WORK/notify.calls")" -eq 1 ]
}

@test "notify-hook: o aviso de outra sessao nao cala esta" {
  export NOTIFY_FORCE=1 OSA_RESULT="ignore"
  run bash -c 'echo "{\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  run bash -c 'echo "{\"session_id\":\"s2\",\"notification_type\":\"permission_prompt\",\"message\":\"precisa de permissão\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--approval' "$WORK/notify.calls")" -eq 2 ]
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

# ---- atencao: AFK, perguntas, tipos desconhecidos ----------------------------

@test "approval: editor na frente mas usuario longe do teclado abre o dialogo" {
  # Saiu para o cafe com o VSCode na frente: o Claude nao pode ficar parado
  # sem aviso nenhum.
  export FAKE_FRONT="Code" FAKE_IDLE_SECS=300 OSA_RESULT="ignore"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/osascript.calls")" == *"dialog.js"* ]]
  [[ "$(cat "$WORK/notify.calls")" == *--approval* ]]
}

@test "approval: o titulo da janela diz qual projeto pede" {
  export NOTIFY_FORCE=1 OSA_RESULT="ignore"
  run bash -c 'echo "{\"cwd\":\"/tmp/projeto-z\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/osascript.calls")" == *"Claude quer usar Bash em projeto-z"* ]]
}

@test "approval: a descricao do comando vai para o banner, o comando nao" {
  export NOTIFY_FORCE=1 OSA_RESULT="ignore"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"export TOKEN=x9\",\"description\":\"Roda a suite\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  banner="$(cat "$WORK/notify.calls")"
  [[ "$banner" == *"Roda a suite"* ]]
  [[ "$banner" != *x9* ]]
}

@test "approval: pergunta do Claude com o usuario fora vira banner, sem dialogo" {
  export FAKE_FRONT="Slack"
  run bash -c 'echo "{\"cwd\":\"/tmp/proj-q\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":{\"questions\":[{\"question\":\"Qual banco usar?\"}]}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$WORK/osascript.calls" ]
  calls="$(cat "$WORK/notify.calls")"
  [[ "$calls" == *"Qual banco usar?"* ]]
  [[ "$calls" == *"proj-q"* ]]
}

@test "approval: plano pronto com o usuario fora vira banner com o titulo do plano" {
  export FAKE_FRONT="Slack"
  run bash -c 'jq -cn --arg p "$(printf "\n# Migrar para plugin\n\nPassos...")" "{tool_name:\"ExitPlanMode\",tool_input:{plan:\$p}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/osascript.calls" ]
  [[ "$(cat "$WORK/notify.calls")" == *"Migrar para plugin"* ]]
}

@test "approval: pergunta com o usuario olhando nao gera nada" {
  export FAKE_FRONT="Code"
  run bash -c 'echo "{\"tool_name\":\"AskUserQuestion\",\"tool_input\":{}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "approval: silenciado nao posta banner nem abre dialogo" {
  export NOTIFY_FORCE=1 MUTE_FILE="$WORK/mute"
  echo forever > "$MUTE_FILE"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/osascript.calls" ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "stop: editor na frente mas usuario longe do teclado notifica" {
  export FAKE_FRONT="Code" FAKE_IDLE_SECS=300
  run bash -c 'echo "{\"cwd\":\"/tmp/meu-projeto\"}" | "$0"' "$WORK/skill/stop-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--done* ]]
}

@test "stop: NOTIFY_AWAY_SECS ajusta quando conta como ausente" {
  export FAKE_FRONT="Code" FAKE_IDLE_SECS=30 NOTIFY_AWAY_SECS=20
  run bash -c 'echo "{\"cwd\":\"/tmp/meu-projeto\"}" | "$0"' "$WORK/skill/stop-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--done* ]]
}

@test "stop: um app Electron qualquer nao conta como editor" {
  export FAKE_FRONT="Electron"
  run bash -c 'echo "{\"cwd\":\"/tmp/meu-projeto\"}" | "$0"' "$WORK/skill/stop-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--done* ]]
}

@test "notify-hook: tipo desconhecido vira info, nunca pedido de aprovacao" {
  run bash -c 'echo "{\"notification_type\":\"quota_auto_resume_fired\",\"message\":\"retomando\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/notify.calls")"
  [[ "$calls" == *retomando* ]]
  [[ "$calls" != *--approval* ]]
}

@test "notify-hook: elicitation_url_dialog e uma espera, como o elicitation_dialog" {
  run bash -c 'echo "{\"notification_type\":\"elicitation_url_dialog\",\"message\":\"abra o link\"}" | "$0"' "$WORK/skill/notify-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *Submarine* ]]
}
