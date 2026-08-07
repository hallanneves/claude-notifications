#!/usr/bin/env bats
# repeat.sh — interval validation, detached lifecycle, recycled-PID safety.

load helpers

setup() {
  common_setup
  copy_skill
  stub_notify   # the reminder loop must never post a real banner
  PIDFILE="$WORK/skill/.repeat.pids"
}

teardown() {
  # Kill only reminders started from this test's disposable copy.
  [ -x "$WORK/skill/repeat.sh" ] && "$WORK/skill/repeat.sh" stop >/dev/null 2>&1 || true
  common_teardown
}

@test "rejeita intervalo nao numerico" {
  run "$WORK/skill/repeat.sh" abc "msg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"intervalo inválido"* ]]
}

@test "rejeita intervalo menor que 5s" {
  run "$WORK/skill/repeat.sh" 3 "msg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mínimo é 5s"* ]]
}

@test "exige mensagem" {
  run "$WORK/skill/repeat.sh" 10
  [ "$status" -ne 0 ]
}

@test "start cria processo detached, list mostra, stop mata" {
  run "$WORK/skill/repeat.sh" 30 "alongar"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reminder started"* ]]
  pid="$(awk 'NR==1 {print $1}' "$PIDFILE")"
  ps -p "$pid" >/dev/null

  run "$WORK/skill/repeat.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"pid $pid"* ]]

  run "$WORK/skill/repeat.sh" stop
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped reminder pid $pid"* ]]
  sleep 0.3
  ! ps -p "$pid" >/dev/null
}

@test "stop nunca mata PID reciclado (sem marker no ps)" {
  echo "1 every 30s: fake" > "$PIDFILE"
  run "$WORK/skill/repeat.sh" stop
  [ "$status" -eq 0 ]
  [[ "$output" != *"stopped reminder pid 1"* ]]
  [ ! -s "$PIDFILE" ]
}

@test "list poda entradas mortas do pidfile" {
  echo "1 every 30s: fake" > "$PIDFILE"
  run "$WORK/skill/repeat.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no active reminders"* ]]
  [ ! -s "$PIDFILE" ]
}
