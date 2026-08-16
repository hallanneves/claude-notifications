#!/usr/bin/env bats
# Alvo do clique — issue #3: cair na janela do projeto certo, nao so no app.

load helpers

setup() {
  common_setup
  copy_skill
  restrict_path
  cat > "$STUB/tn" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$WORK/tn.args"
EOF
  chmod +x "$STUB/tn"
}

teardown() { common_teardown; }

@test "clique: sem projeto, so ativa o app" {
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *$'-activate\ncom.microsoft.VSCode'* ]]
}

@test "clique: com projeto, abre a pasta no editor" {
  NOTIFY_TARGET_PATH="/tmp/meu-projeto" NOTIFY_TN="$STUB/tn" \
    run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"open -b com.microsoft.VSCode '/tmp/meu-projeto'"* ]]
  [[ "$args" != *"-activate"* ]]
}

@test "clique: terminal nao recebe a pasta (abriria uma janela nova)" {
  NOTIFY_ACTIVATE="com.googlecode.iterm2" NOTIFY_TARGET_PATH="/tmp/meu-projeto" \
    NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *$'-activate\ncom.googlecode.iterm2'* ]]
}

@test "clique: NOTIFY_ACTIVATE_PATH=always força a pasta em qualquer app" {
  NOTIFY_ACTIVATE="com.googlecode.iterm2" NOTIFY_ACTIVATE_PATH=always \
    NOTIFY_TARGET_PATH="/tmp/p" NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *"open -b com.googlecode.iterm2 '/tmp/p'"* ]]
}

@test "clique: NOTIFY_ACTIVATE_PATH=never volta ao comportamento antigo" {
  NOTIFY_ACTIVATE_PATH=never NOTIFY_TARGET_PATH="/tmp/p" \
    NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *$'-activate\ncom.microsoft.VSCode'* ]]
}

@test "clique: Cursor tambem conta como editor" {
  NOTIFY_ACTIVATE="com.todesktop.230313mzl4w4u92" NOTIFY_TARGET_PATH="/tmp/p" \
    NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *"open -b com.todesktop.230313mzl4w4u92 '/tmp/p'"* ]]
}

@test "clique: stop-hook manda o cwd do projeto" {
  stub_lsappinfo
  export FAKE_FRONT="Slack"
  run bash -c 'echo "{\"cwd\":\"/tmp/projeto-x\"}" | NOTIFY_TN='"$STUB"'/tn "$0"' "$WORK/skill/stop-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *"open -b com.microsoft.VSCode '/tmp/projeto-x'"* ]]
}

@test "clique: 'Abrir no editor' abre a pasta daquela sessao" {
  stub_notify
  stub_lsappinfo
  stub_osascript
  stub_open
  export NOTIFY_FORCE=1 OSA_RESULT="editor"
  run bash -c 'echo "{\"cwd\":\"/tmp/projeto-y\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' \
    "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/open.calls")" == *"/tmp/projeto-y"* ]]
}
