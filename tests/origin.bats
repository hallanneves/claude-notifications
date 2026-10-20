#!/usr/bin/env bats
# detect_origin e o gate de atencao: de onde a sessao vem (pela arvore de
# processos, nao pelo ambiente) e se voce esta olhando para ELA.

load helpers

setup() {
  common_setup
  copy_skill
  stub_lsappinfo
  stub_notify
  stub_osascript
  restrict_path
  TERMINAL="$(fake_app Terminal com.apple.Terminal)"
  ITERM="$(fake_app iTerm2 com.googlecode.iterm2)"
  CODE="$(fake_app "Visual Studio Code" com.microsoft.VSCode)"
  CODE_APP="${CODE%%.app/*}.app"
  PLUGIN_HOST="$CODE_APP/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"
  PTY_HOST="$CODE_APP/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
  # O hook "roda" como pid 100 em todas as arvores abaixo.
  export NOTIFY_PID=100
}

teardown() { common_teardown; }

origin() {
  bash -c '. "$1/skill/notify-lib.sh"; detect_origin; printf "%s|%s" "$ORIGIN_KIND" "$ORIGIN_BUNDLE"' _ "$WORK"
}

# Claude num pane do herdr; o cliente herdr roda numa aba do Terminal.
herdr_tree() {
  fake_ps "100 90 ttys005 /bin/bash" "90 80 ttys005 claude" "80 70 ttys005 -zsh" \
    "70 1 ?? /opt/homebrew/bin/herdr" \
    "200 1 ?? $TERMINAL" "210 200 ttys000 login" "220 210 ttys000 -zsh" "230 220 ttys000 herdr"
  export HERDR_PANE_ID="w3:p1"
}

terminal_tree() {
  fake_ps "100 90 ttys004 /bin/bash" "90 80 ttys004 claude" "80 70 ttys004 -zsh" \
    "70 60 ttys004 login" "60 1 ?? $TERMINAL"
}

# ---- de onde vem ---------------------------------------------------------------

@test "origem: pane do herdr" {
  herdr_tree
  run origin
  [ "$output" = "herdr|" ]
}

@test "origem: aba do Terminal.app" {
  terminal_tree
  run origin
  [ "$output" = "app|com.apple.Terminal" ]
}

@test "origem: painel do Claude no VSCode (extension host)" {
  fake_ps "100 90 ?? /bin/bash" "90 80 ?? claude" "80 50 ?? $PLUGIN_HOST" "50 1 ?? $CODE"
  run origin
  [ "$output" = "editor-extension|com.microsoft.VSCode" ]
}

@test "origem: terminal integrado do VSCode" {
  fake_ps "100 90 ttys009 /bin/bash" "90 80 ttys009 claude" "80 70 ttys009 -zsh" \
    "70 50 ?? $PTY_HOST" "50 1 ?? $CODE"
  run origin
  [ "$output" = "editor-terminal|com.microsoft.VSCode" ]
}

@test "origem: tmux" {
  fake_ps "100 90 ttys006 /bin/bash" "90 80 ttys006 claude" "80 70 ttys006 -zsh" "70 1 ?? tmux"
  run origin
  [ "$output" = "tmux|" ]
}

@test "origem: variaveis do herdr vazadas nao enganam a arvore" {
  # Um "code ." aberto de dentro de um pane leva HERDR_* para o VSCode.
  export HERDR_ENV=1 HERDR_PANE_ID="w1:p1" TERM_PROGRAM="herdr"
  fake_ps "100 90 ttys009 /bin/bash" "90 80 ttys009 claude" "80 70 ttys009 -zsh" \
    "70 50 ?? $PTY_HOST" "50 1 ?? $CODE"
  run origin
  [ "$output" = "editor-terminal|com.microsoft.VSCode" ]
}

@test "origem: sem arvore conhecida e desconhecida" {
  run origin
  [ "$output" = "unknown|" ]
}

# ---- voce esta olhando? -------------------------------------------------------

stop() {
  run bash -c 'echo "{\"session_id\":\"s1\",\"cwd\":\"/tmp/proj\"}" | "$0"' "$WORK/skill/stop-hook.sh"
}

@test "gate: VSCode na frente com a sessao no Terminal notifica" {
  # Estar num editor nao e estar olhando uma sessao que roda no Terminal.
  terminal_tree
  export FAKE_FRONT="Code"
  stop
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--done* ]]
}

@test "gate: Terminal na frente com a sessao no Terminal fica quieto" {
  terminal_tree
  export FAKE_FRONT="Terminal"
  stop
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "gate: herdr com este pane na tela fica quieto" {
  herdr_tree
  export FAKE_FRONT="Terminal" FAKE_HERDR_GET='{"result":{"agent":{"focused":true}}}'
  stop
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/notify.calls" ]
  [[ "$(cat "$WORK/herdr.calls")" == *"agent get w3:p1"* ]]
}

@test "gate: herdr com outro pane na tela notifica" {
  herdr_tree
  export FAKE_FRONT="Terminal" FAKE_HERDR_GET='{"result":{"agent":{"focused":false}}}'
  stop
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--done* ]]
}

@test "gate: herdr com o Terminal atras de outro app notifica" {
  herdr_tree
  export FAKE_FRONT="Code" FAKE_HERDR_GET='{"result":{"agent":{"focused":true}}}'
  stop
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *--done* ]]
}

@test "gate: herdr usa o app do cliente, nao o __CFBundleIdentifier herdado" {
  # O servidor herdr herda o bundle de quem o iniciou (aqui, um iTerm velho);
  # quem mostra a sessao e o Terminal onde o cliente roda.
  herdr_tree
  export __CFBundleIdentifier="com.googlecode.iterm2"
  export FAKE_FRONT="Terminal" FAKE_HERDR_GET='{"result":{"agent":{"focused":true}}}'
  stop
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "gate: herdr que nao responde cai no gate por app" {
  herdr_tree
  export FAKE_FRONT="Terminal"
  stop
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "gate: aprovacao com outro pane do herdr na tela abre o dialogo" {
  herdr_tree
  export FAKE_FRONT="Terminal" FAKE_HERDR_GET='{"result":{"agent":{"focused":false}}}' OSA_RESULT="ignore"
  run bash -c 'echo "{\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/osascript.calls")" == *"dialog.js"* ]]
}

@test "stop: no herdr o subtitulo traz o titulo da sessao" {
  herdr_tree
  export FAKE_FRONT="Slack" FAKE_HERDR_GET='{"result":{"agent":{"focused":false,"terminal_title_stripped":"Refatorar login"}}}'
  stop
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/notify.calls")" == *"Refatorar login"* ]]
}
