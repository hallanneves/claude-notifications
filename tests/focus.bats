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
  [[ "$(cat "$WORK/osascript.scripts")" == *"iTerm2"* ]]
  [[ "$(cat "$WORK/osascript.calls")" == *"ABC-123"* ]]
  # Nao caiu no fallback de abrir o app.
  [ ! -f "$WORK/open.calls" ]
}

@test "focus: Terminal.app seleciona a aba pelo tty" {
  run "$WORK/skill/focus.sh" /tmp/proj "Apple_Terminal" "" "/dev/ttys004"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/osascript.scripts")" == *'tell application "Terminal"'* ]]
  [[ "$(cat "$WORK/osascript.calls")" == *"/dev/ttys004"* ]]
  [ ! -f "$WORK/open.calls" ]
}

@test "focus: valores chegam ao AppleScript por argv, nunca dentro do codigo" {
  run "$WORK/skill/focus.sh" /tmp/proj "Apple_Terminal" "" '/dev/ttys004" & do shell script "touch /tmp/x'
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/osascript.scripts")" != *ttys004* ]]
  [[ "$(cat "$WORK/osascript.calls")" == *'do shell script'* ]]
}

@test "focus: aba do Terminal que sumiu cai no Terminal, nunca no VSCode" {
  stub_notify
  export OSA_ERR="execution error: tab not found (-2700)"
  run "$WORK/skill/focus.sh" /tmp/proj "Apple_Terminal" "" "/dev/ttys004" "com.apple.Terminal"
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/open.calls")"
  [[ "$calls" == *"com.apple.Terminal"* ]]
  [[ "$calls" != *"VSCode"* ]]
  [[ "$calls" != *"/tmp/proj"* ]]
  # Sessao fechada nao e falta de permissao: sem banner de dica.
  [ ! -f "$WORK/notify.calls" ]
}

@test "focus: Automacao negada cai no app certo e avisa uma vez so" {
  stub_notify
  export OSA_ERR="execution error: Not authorized to send Apple events to Terminal. (-1743)"
  run "$WORK/skill/focus.sh" /tmp/proj "Apple_Terminal" "" "/dev/ttys004" "com.apple.Terminal"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/open.calls")" == *"com.apple.Terminal"* ]]
  [[ "$(cat "$WORK/notify.calls")" == *"Automação"* ]]
  [[ "$(cat "$WORK/notify.calls")" == *"x-apple.systempreferences"* ]]
  run "$WORK/skill/focus.sh" /tmp/proj "Apple_Terminal" "" "/dev/ttys004" "com.apple.Terminal"
  [ "$(grep -c 'Privacidade e Segurança' "$WORK/notify.calls")" -eq 1 ]
}

@test "focus: VSCode abre a raiz do workspace, nunca a subpasta" {
  # open -b com uma subpasta cria uma janela nova em vez de focar a existente.
  make_ide_lock $$ /tmp/mono
  run "$WORK/skill/focus.sh" /tmp/mono/packages/api "" "" "" "com.microsoft.VSCode"
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/open.calls")"
  [[ "$calls" == *$'com.microsoft.VSCode\n/tmp/mono'* ]]
  [[ "$calls" != *"packages/api"* ]]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "focus: entre workspaces aninhados vence o mais especifico" {
  make_ide_lock $$ /tmp/mono /tmp/mono/packages/api
  run "$WORK/skill/focus.sh" /tmp/mono/packages/api/src "" "" "" "com.microsoft.VSCode"
  [[ "$(cat "$WORK/open.calls")" == *"/tmp/mono/packages/api"* ]]
}

@test "focus: sem janela conhecida para o projeto, so ativa o editor" {
  make_ide_lock $$ /tmp/outro-projeto
  run "$WORK/skill/focus.sh" /tmp/proj "" "" "" "com.microsoft.VSCode"
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/open.calls")" = $'-b\ncom.microsoft.VSCode' ]
}

@test "focus: lock de uma janela que ja fechou e ignorado" {
  make_ide_lock 999999 /tmp/proj
  run "$WORK/skill/focus.sh" /tmp/proj "" "" "" "com.microsoft.VSCode"
  [ "$(cat "$WORK/open.calls")" = $'-b\ncom.microsoft.VSCode' ]
}

@test "focus: cwd com aspa simples nao quebra nem injeta comando" {
  make_ide_lock $$ "/tmp/x'; touch $WORK/pwned; '"
  run "$WORK/skill/focus.sh" "/tmp/x'; touch $WORK/pwned; '" "" "" "" "com.microsoft.VSCode"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/pwned" ]
  grep -qxF "/tmp/x'; touch $WORK/pwned; '" "$WORK/open.calls"
}

@test "focus: NOTIFY_ACTIVATE_PATH=always manda o cwd mesmo sem lock" {
  NOTIFY_ACTIVATE_PATH=always run "$WORK/skill/focus.sh" /tmp/proj "" "" "" "com.microsoft.VSCode"
  [[ "$(cat "$WORK/open.calls")" == *"/tmp/proj"* ]]
}

@test "focus: sem host conhecido nao chuta app nenhum" {
  run "$WORK/skill/focus.sh" "" "" "" ""
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/open.calls" ]
}

@test "focus: o banner carrega a identidade da sessao no clique" {
  ITERM_SESSION_ID="w0t1p0:XYZ-789" TERM_PROGRAM="iTerm.app" __CFBundleIdentifier="com.googlecode.iterm2" \
    NOTIFY_TARGET_PATH="/tmp/proj" NOTIFY_TN="$STUB/tn" \
    run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"focus.sh"* ]]
  [[ "$args" == *"XYZ-789"* ]]
  [[ "$args" == *"/tmp/proj"* ]]
}

@test "focus: caminho com aspas nao quebra o comando do clique" {
  __CFBundleIdentifier="com.microsoft.VSCode" NOTIFY_TARGET_PATH="/tmp/it's here" NOTIFY_TN="$STUB/tn" \
    run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  # A citacao tem que sobreviver: o clique roda isso como comando de shell.
  cmd="$(grep -A0 "focus.sh" "$WORK/tn.args" | tail -1)"
  run bash -c "set -- $cmd; while [ \$# -gt 0 ]; do [ \"\$1\" = --cwd ] && printf '%s' \"\$2\"; shift; done"
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

@test "focus: ITERM_SESSION_ID herdado dentro de um multiplexador e ignorado" {
  # O herdr/tmux herda o id do iTerm que subiu o servidor: focaria uma aba
  # que nao tem nada a ver com esta sessao.
  ITERM_SESSION_ID="w0t0p0:VELHO" TERM_PROGRAM="herdr" __CFBundleIdentifier="com.apple.Terminal" \
    NOTIFY_TARGET_PATH="/tmp/proj" NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" != *VELHO* ]]
}

@test "focus: herdr no Terminal nunca abre o VSCode" {
  TERM_PROGRAM="herdr" __CFBundleIdentifier="com.apple.Terminal" \
    NOTIFY_TARGET_PATH="/tmp/proj" NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *$'-activate\ncom.apple.Terminal'* ]]
  [[ "$args" != *VSCode* ]]
}

# ---- herdr ---------------------------------------------------------------------

herdr_client_tree() {
  TERMINAL="$(fake_app Terminal com.apple.Terminal)"
  fake_ps "200 1 ?? $TERMINAL" "210 200 ttys000 login" "220 210 ttys000 -zsh" "230 220 ttys000 herdr" \
    "70 1 ?? /opt/homebrew/bin/herdr"
}

herdr_focus() {
  run "$WORK/skill/focus.sh" --cwd /tmp/proj --kind herdr --host com.apple.Terminal \
    --herdr-bin "$STUB/herdr" --herdr-socket /tmp/herdr.sock --herdr-pane "${PANE:-w9:p9}" \
    --session S1 --report "$WORK/report"
}

@test "focus: herdr acha o pane pela sessao, foca e levanta a aba do cliente" {
  # O id do pane muda quando ele e movido; o da sessao do Claude, nao.
  herdr_client_tree
  export FAKE_HERDR_LIST='{"result":{"agents":[{"pane_id":"w2:p1","agent_session":{"value":"S1"}}]}}'
  herdr_focus
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/herdr.calls")" == *"agent focus w2:p1"* ]]
  [[ "$(cat "$WORK/osascript.scripts")" == *'tell application "Terminal"'* ]]
  [[ "$(cat "$WORK/osascript.calls")" == *"/dev/ttys000"* ]]
  [[ "$(cat "$WORK/report")" == *"herdr-pane w2:p1"* ]]
  [[ "$(cat "$WORK/report")" == *"terminal-tab com.apple.Terminal /dev/ttys000"* ]]
  [ ! -f "$WORK/open.calls" ]
}

@test "focus: herdr sem a sessao na lista usa o pane gravado no clique" {
  herdr_client_tree
  export FAKE_HERDR_LIST='{"result":{"agents":[]}}'
  PANE="w3:p1" herdr_focus
  [[ "$(cat "$WORK/herdr.calls")" == *"agent focus w3:p1"* ]]
}

@test "focus: herdr sem cliente anexado so ativa o app do host" {
  fake_ps "70 1 ?? /opt/homebrew/bin/herdr"
  herdr_focus
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/open.calls")" = $'-b\ncom.apple.Terminal' ]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "focus: herdr com o cliente no iTerm2 foca a sessao pelo tty" {
  ITERM="$(fake_app iTerm2 com.googlecode.iterm2)"
  fake_ps "300 1 ?? $ITERM" "310 300 ttys002 login" "320 310 ttys002 -zsh" "330 320 ttys002 herdr"
  herdr_focus
  [ "$status" -eq 0 ]
  scripts="$(cat "$WORK/osascript.scripts")"
  [[ "$scripts" == *'tell application "iTerm2"'* ]]
  [[ "$scripts" == *"tty of s"* ]]
  [[ "$(cat "$WORK/osascript.calls")" == *"/dev/ttys002"* ]]
}

@test "focus: herdr inacessivel ainda levanta a aba do terminal" {
  herdr_client_tree
  export FAKE_HERDR_FOCUS_RC=1
  herdr_focus
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/report")" != *"herdr-pane"* ]]
  [[ "$(cat "$WORK/report")" == *"terminal-tab"* ]]
}

@test "focus: o clique de uma sessao do herdr leva pane, sessao e socket" {
  fake_ps "100 90 ttys005 /bin/bash" "90 70 ttys005 claude" "70 1 ?? /opt/homebrew/bin/herdr"
  NOTIFY_PID=100 HERDR_PANE_ID="w3:p1" HERDR_SOCKET_PATH="/tmp/h.sock" NOTIFY_SESSION="S1" \
    __CFBundleIdentifier="com.apple.Terminal" NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "ok"
  [ "$status" -eq 0 ]
  args="$(cat "$WORK/tn.args")"
  [[ "$args" == *"'--kind' 'herdr'"* ]]
  [[ "$args" == *"'--herdr-pane' 'w3:p1'"* ]]
  [[ "$args" == *"'--session' 'S1'"* ]]
  [[ "$args" == *"'--herdr-socket' '/tmp/h.sock'"* ]]
}
