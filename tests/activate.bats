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
  export NOTIFY_TTY="" TERM_PROGRAM="" ITERM_SESSION_ID=""
}

teardown() { common_teardown; }

@test "clique: sem projeto, so ativa o app que hospeda a sessao" {
  __CFBundleIdentifier="com.microsoft.VSCode" NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *$'-activate\ncom.microsoft.VSCode'* ]]
}

@test "clique: o app vem do host da sessao, nao de um editor fixo" {
  __CFBundleIdentifier="com.apple.Terminal" NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *$'-activate\ncom.apple.Terminal'* ]]
  [[ "$args" != *VSCode* ]]
}

@test "clique: Terminal.app identificado pelo TERM_PROGRAM" {
  TERM_PROGRAM="Apple_Terminal" NOTIFY_TTY="" NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *"com.apple.Terminal"* ]]
}

@test "clique: sem host conhecido nao chuta o VSCode" {
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" != *VSCode* ]]
}

@test "clique: com projeto, abre a pasta no editor" {
  __CFBundleIdentifier="com.microsoft.VSCode" NOTIFY_TARGET_PATH="/tmp/meu-projeto" NOTIFY_TN="$STUB/tn" \
    run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"focus.sh"* ]]
  [[ "$args" == *"/tmp/meu-projeto"* ]]
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
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"focus.sh"* ]]
  [[ "$args" == *"/tmp/p"* ]]
}

@test "clique: NOTIFY_ACTIVATE_PATH=never volta ao comportamento antigo" {
  __CFBundleIdentifier="com.microsoft.VSCode" NOTIFY_ACTIVATE_PATH=never NOTIFY_TARGET_PATH="/tmp/p" \
    NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *$'-activate\ncom.microsoft.VSCode'* ]]
}

@test "clique: Cursor tambem conta como editor" {
  NOTIFY_ACTIVATE="com.todesktop.230313mzl4w4u92" NOTIFY_TARGET_PATH="/tmp/p" \
    NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"focus.sh"* ]]
  [[ "$args" == *"/tmp/p"* ]]
}

@test "clique: stop-hook manda o cwd do projeto" {
  stub_lsappinfo
  export FAKE_FRONT="Slack" __CFBundleIdentifier="com.microsoft.VSCode"
  run bash -c 'echo "{\"cwd\":\"/tmp/projeto-x\"}" | NOTIFY_TN='"$STUB"'/tn "$0"' "$WORK/skill/stop-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *"/tmp/projeto-x"* ]]
}

@test "clique: 'Ir para a sessao' abre a janela daquela sessao" {
  stub_notify
  stub_lsappinfo
  stub_osascript
  stub_open
  make_ide_lock $$ /tmp/projeto-y
  export NOTIFY_FORCE=1 OSA_RESULT="editor" __CFBundleIdentifier="com.microsoft.VSCode"
  run bash -c 'echo "{\"cwd\":\"/tmp/projeto-y\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' \
    "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/open.calls")" == *"/tmp/projeto-y"* ]]
}
