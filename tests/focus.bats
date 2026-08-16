#!/usr/bin/env bats
# focus.sh — voltar exatamente para onde a notificacao nasceu.
# A aba de terminal so e alcancavel quando o host expoe uma; editor para na
# janela do projeto, que e o teto do que VSCode e afins permitem.

load helpers

setup() {
  common_setup
  copy_skill
  restrict_path
  stub_open
  stub_osascript
  # Sem TTY e sem id de sessao por padrao: o caso "extensao do editor".
  export NOTIFY_TTY="" TERM_PROGRAM="" ITERM_SESSION_ID=""
  cat > "$STUB/tn" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$WORK/tn.args"
EOF
  chmod +x "$STUB/tn"
}

teardown() { common_teardown; }

@test "focus: iTerm2 seleciona a sessao pelo id" {
  ITERM_SESSION_ID="w0t1p0:ABC-123" run "$WORK/skill/focus.sh" /tmp/proj "iTerm.app" "w0t1p0:ABC-123" ""
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/osascript.calls")"
  [[ "$calls" == *"iTerm2"* ]]
  [[ "$calls" == *"ABC-123"* ]]
  # Nao caiu no fallback de abrir o app.
  [ ! -f "$WORK/open.calls" ]
}

@test "focus: Terminal.app seleciona a aba pelo tty" {
  run "$WORK/skill/focus.sh" /tmp/proj "Apple_Terminal" "" "/dev/ttys004"
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/osascript.calls")"
  [[ "$calls" == *'tell application "Terminal"'* ]]
  [[ "$calls" == *"/dev/ttys004"* ]]
  [ ! -f "$WORK/open.calls" ]
}

@test "focus: sessao de terminal que sumiu cai na janela do projeto" {
  # osascript falhando = sessao nao encontrada.
  cat > "$STUB/osascript" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$STUB/osascript"
  run "$WORK/skill/focus.sh" /tmp/proj "Apple_Terminal" "" "/dev/ttys004"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/open.calls")" == *"/tmp/proj"* ]]
}

@test "focus: sem identidade de terminal, abre a pasta no editor" {
  run "$WORK/skill/focus.sh" /tmp/proj "" "" ""
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/open.calls")" == *"/tmp/proj"* ]]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "focus: nem pasta nem terminal, so ativa o app" {
  run "$WORK/skill/focus.sh" "" "" "" ""
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/open.calls")"
  [[ "$calls" == *"com.microsoft.VSCode"* ]]
}

@test "focus: o banner carrega a identidade da sessao no clique" {
  ITERM_SESSION_ID="w0t1p0:XYZ-789" TERM_PROGRAM="iTerm.app" \
    NOTIFY_TARGET_PATH="/tmp/proj" NOTIFY_TN="$STUB/tn" \
    run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"focus.sh"* ]]
  [[ "$args" == *"XYZ-789"* ]]
  [[ "$args" == *"/tmp/proj"* ]]
}

@test "focus: caminho com aspas nao quebra o comando do clique" {
  NOTIFY_TARGET_PATH="/tmp/it's here" NOTIFY_TN="$STUB/tn" \
    run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  # A citacao tem que sobreviver: o clique roda isso como comando de shell.
  cmd="$(grep -A0 "focus.sh" "$WORK/tn.args" | tail -1)"
  run bash -c "set -- $cmd; printf '%s' \"\$2\""
  [ "$output" = "/tmp/it's here" ]
}

@test "focus: terminal sem TTY (extensao do editor) nao inventa aba" {
  NOTIFY_TTY="??" TERM_PROGRAM="Apple_Terminal" NOTIFY_TARGET_PATH="/tmp/proj" \
    NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"focus.sh"* ]]
  # O quarto argumento (tty) sai vazio.
  [[ "$args" == *"'' ''"* ]] || [[ "$args" == *"''"* ]]
}
