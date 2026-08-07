#!/usr/bin/env bats
# notify.sh — presets, overrides, sound validation and the osascript fallback.

load helpers

setup() {
  common_setup
  copy_skill
  cat > "$STUB/tn" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$WORK/tn.args"
EOF
  chmod +x "$STUB/tn"
}

teardown() { common_teardown; }

tn_args() { cat "$WORK/tn.args"; }

@test "--done preseta titulo Trabalho concluido e som Hero" {
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "build ok"
  [ "$status" -eq 0 ]
  args="$(tn_args)"
  [[ "$args" == *$'-title\nTrabalho concluído'* ]]
  [[ "$args" == *$'-sound\nHero'* ]]
  [[ "$args" == *$'-message\nbuild ok'* ]]
}

@test "--fail preseta titulo Algo falhou e som Basso" {
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --fail "build quebrou"
  [ "$status" -eq 0 ]
  args="$(tn_args)"
  [[ "$args" == *$'-title\nAlgo falhou'* ]]
  [[ "$args" == *$'-sound\nBasso'* ]]
}

@test "sem flag usa o preset info (Claude Code + Glass)" {
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" "mensagem"
  [ "$status" -eq 0 ]
  args="$(tn_args)"
  [[ "$args" == *$'-title\nClaude Code'* ]]
  [[ "$args" == *$'-sound\nGlass'* ]]
}

@test "titulo, subtitulo e som explicitos sobrepoem o preset" {
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "x" "Meu título" "meu sub" "Ping"
  [ "$status" -eq 0 ]
  args="$(tn_args)"
  [[ "$args" == *$'-title\nMeu título'* ]]
  [[ "$args" == *$'-sound\nPing'* ]]
  [[ "$args" == *$'-subtitle\nmeu sub'* ]]
}

@test "sem mensagem falha com usage" {
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *usage* ]]
}

@test "som inexistente avisa mas ainda notifica" {
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" "msg" "" "" "SomQueNaoExiste123"
  [ "$status" -eq 0 ]
  [[ "$output" == *"não existe"* ]]
  [[ "$(tn_args)" == *$'-sound\nSomQueNaoExiste123'* ]]
}

@test "notify.conf define NOTIFY_ACTIVATE" {
  mkdir -p "$HOME/.claude/skills/notify"
  echo 'NOTIFY_ACTIVATE="com.example.editor"' > "$HOME/.claude/skills/notify/notify.conf"
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" "msg"
  [ "$status" -eq 0 ]
  [[ "$(tn_args)" == *$'-activate\ncom.example.editor'* ]]
}

@test "fallback osascript escapa aspas e barras invertidas" {
  stub_osascript
  restrict_path
  run "$WORK/skill/notify.sh" 'msg com "aspas" e \barra'
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/osascript.calls")"
  [[ "$calls" == *'display notification "msg com \"aspas\" e \\barra"'* ]]
}
