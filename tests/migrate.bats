#!/usr/bin/env bats
# migrate.sh — da instalacao pre-2.0 (copia em ~/.claude/skills/notify, hooks
# no settings.json) para o plugin, sem perder config, silencio nem hooks alheios.

load helpers

setup() {
  common_setup
  copy_repo
  restrict_path
  stub_claude
  SETTINGS="$HOME/.claude/settings.json"
  MIGRATE="$WORK/repo/skills/notify/migrate.sh"
}

teardown() {
  [ -n "${LEGACY_PID:-}" ] && kill "$LEGACY_PID" 2>/dev/null
  [ -n "${PLUGIN_PID:-}" ] && kill "$PLUGIN_PID" 2>/dev/null
  common_teardown
}

# O plugin instalado, como o `claude plugin install` deixa registrado.
plugin_in() { "$STUB/claude" plugin install notify --marketplace hallanneves/claude-notifications >/dev/null; }

@test "migrate: sem o plugin instalado, recusa e nao mexe em nada" {
  make_legacy_install
  before="$(cat "$SETTINGS")"
  run "$MIGRATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/plugin install notify"* ]]
  [ "$(cat "$SETTINGS")" = "$before" ]
  [ -d "$HOME/.claude/skills/notify" ]
}

@test "migrate: tira so os hooks antigos, com backup, e remove a copia antiga" {
  make_legacy_install
  plugin_in
  run "$MIGRATE"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks | tostring | contains(".claude/skills/notify/")' "$SETTINGS")" = "false" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" = "other-tool.sh" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS")" = "linter.sh" ]
  [ "$(jq '.hooks | has("PermissionRequest")' "$SETTINGS")" = "false" ]
  backup="$(find "$HOME/.claude" -name 'settings.json.bak.*')"
  [ -n "$backup" ]
  [ "$(jq '.hooks | tostring | contains(".claude/skills/notify/")' "$backup")" = "true" ]
  [ ! -d "$HOME/.claude/skills/notify" ]
  [[ "$output" == *"Reinicie"* ]]
}

@test "migrate: config e silencio da instalacao antiga sobrevivem" {
  make_legacy_install
  plugin_in
  echo 'NOTIFY_LANG="en"' > "$HOME/.claude/skills/notify/notify.conf"
  echo forever > "$HOME/.claude/skills/notify/.mute-until"
  run "$MIGRATE"
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/notify.conf")" = 'NOTIFY_LANG="en"' ]
  [ "$(cat "$STATE/.mute-until")" = "forever" ]
  run env -u NOTIFY_LANG "$WORK/repo/skills/notify/mute.sh" status
  [[ "$output" == *"muted"* ]]
}

@test "migrate: config nova ja existente fica, a antiga e guardada ao lado" {
  make_legacy_install
  plugin_in
  mkdir -p "$STATE"
  echo 'NOTIFY_LANG="pt"' > "$STATE/notify.conf"
  echo 'NOTIFY_LANG="en"' > "$HOME/.claude/skills/notify/notify.conf"
  run "$MIGRATE"
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/notify.conf")" = 'NOTIFY_LANG="pt"' ]
  [ "$(cat "$STATE/notify.conf.legacy")" = 'NOTIFY_LANG="en"' ]
}

@test "migrate: rodar de novo nao faz nada nem cria outro backup" {
  make_legacy_install
  plugin_in
  "$MIGRATE" >/dev/null
  before="$(cat "$SETTINGS")"
  run "$MIGRATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nada a migrar"* ]]
  [ "$(cat "$SETTINGS")" = "$before" ]
  [ "$(find "$HOME/.claude" -name 'settings.json.bak.*' | wc -l | tr -d ' ')" = "1" ]
}

@test "migrate: para os lembretes da copia antiga e deixa os do plugin" {
  make_legacy_install
  plugin_in
  # Um lembrete de cada geracao: o antigo nao tem "from=".
  bash -c '# claude-notify-repeat
while true; do sleep 30; done' >/dev/null 2>&1 &
  LEGACY_PID=$!
  bash -c "# claude-notify-repeat from=$WORK/repo/skills/notify
while true; do sleep 30; done" >/dev/null 2>&1 &
  PLUGIN_PID=$!
  mkdir -p "$STATE"
  printf '%s every 60s: velho\n%s every 60s: novo\n' "$LEGACY_PID" "$PLUGIN_PID" > "$STATE/.repeat.pids"
  run "$MIGRATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"velho"* ]]
  sleep 0.2
  ! kill -0 "$LEGACY_PID" 2>/dev/null
  kill -0 "$PLUGIN_PID"
  [ "$(cat "$STATE/.repeat.pids")" = "$PLUGIN_PID every 60s: novo" ]
}

@test "migrate: --force migra mesmo sem o plugin registrado" {
  make_legacy_install
  run "$MIGRATE" --force
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.claude/skills/notify" ]
}

@test "migrate: sistema limpo nao falha" {
  plugin_in
  run "$MIGRATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nada a migrar"* ]]
}
