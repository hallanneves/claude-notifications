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
  export NOTIFY_FORCE=1 OSA_RESULT="button returned:Aprovar, gave up:false"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.behavior')" = "allow" ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.updatedInput.command')" = "ls -la" ]
}

@test "approval: Negar devolve behavior deny" {
  export NOTIFY_FORCE=1 OSA_RESULT="button returned:Negar, gave up:false"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm x\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.behavior')" = "deny" ]
}

@test "approval: timeout (gave up) cai no fail-safe sem output" {
  export NOTIFY_FORCE=1 OSA_RESULT="button returned:Abrir no editor, gave up:true"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "approval: Abrir no editor foca o editor e nao decide" {
  export NOTIFY_FORCE=1 OSA_RESULT="button returned:Abrir no editor, gave up:false"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$(cat "$WORK/open.calls")" == *"com.microsoft.VSCode"* ]]
}

@test "approval: comando longo e truncado com aviso explicito" {
  export NOTIFY_FORCE=1 OSA_RESULT="button returned:Negar, gave up:false"
  long="$(printf 'a%.0s' $(seq 1 400))"
  run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long\"}}' | \"\$0\"" "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/osascript.calls")" == *"[TRUNCADO"* ]]
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
