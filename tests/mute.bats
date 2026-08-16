#!/usr/bin/env bats
# mute.sh — issue #2: silenciar notificacoes para trabalho focado.

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
  export MUTE_FILE="$WORK/mute-until"
}

teardown() { common_teardown; }

@test "mute: status inicial e ligado" {
  run "$WORK/skill/mute.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"notificações ligadas"* ]]
}

@test "mute: silencia por duracao e o banner nao sai" {
  run "$WORK/skill/mute.sh" 30m
  [ "$status" -eq 0 ]
  [[ "$output" == *"silenciadas até"* ]]

  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "nao deve aparecer"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/tn.args" ]
}

@test "mute: off religa e o banner volta" {
  "$WORK/skill/mute.sh" 30m >/dev/null
  run "$WORK/skill/mute.sh" off
  [ "$status" -eq 0 ]
  [[ "$output" == *"ligadas"* ]]

  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "deve aparecer"
  [ "$status" -eq 0 ]
  [ -f "$WORK/tn.args" ]
}

@test "mute: on silencia por tempo indeterminado" {
  run "$WORK/skill/mute.sh" on
  [ "$status" -eq 0 ]
  [[ "$output" == *"até você religar"* ]]
  [ "$(cat "$MUTE_FILE")" = "forever" ]
}

@test "mute: carimbo vencido se limpa sozinho" {
  echo "1" > "$MUTE_FILE"   # 1970
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "deve aparecer"
  [ "$status" -eq 0 ]
  [ -f "$WORK/tn.args" ]
  [ ! -f "$MUTE_FILE" ]
}

@test "mute: carimbo corrompido nao silencia para sempre" {
  echo "lixo" > "$MUTE_FILE"
  NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "deve aparecer"
  [ "$status" -eq 0 ]
  [ -f "$WORK/tn.args" ]
  [ ! -f "$MUTE_FILE" ]
}

@test "mute: duracao invalida e recusada" {
  run "$WORK/skill/mute.sh" "amanha"
  [ "$status" -eq 1 ]
  [[ "$output" == *"inválida"* ]]
  [ ! -f "$MUTE_FILE" ]
}

@test "mute: numero puro conta como minutos" {
  run "$WORK/skill/mute.sh" 2
  [ "$status" -eq 0 ]
  now="$(date +%s)"
  until="$(cat "$MUTE_FILE")"
  [ "$((until - now))" -gt 100 ]
  [ "$((until - now))" -le 120 ]
}

@test "mute: silencia tambem o DIALOGO de aprovacao" {
  stub_notify
  stub_lsappinfo
  stub_osascript
  "$WORK/skill/mute.sh" 30m >/dev/null
  export NOTIFY_FORCE=1 OSA_RESULT="approve"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf /\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  # Nada de janela e, acima de tudo, nenhuma decisao: cai no prompt do terminal.
  [ -z "$output" ]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "mute: o banner de atualizacao tambem respeita o silencio" {
  echo "1.0.0" > "$WORK/skill/VERSION"
  remote="$(make_fake_remote v9.9.9)"
  "$WORK/skill/mute.sh" 30m >/dev/null
  NOTIFY_TN="$STUB/tn" NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh" --force
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/tn.args" ]
}
