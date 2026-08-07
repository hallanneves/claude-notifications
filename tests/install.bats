#!/usr/bin/env bats
# install.sh / uninstall.sh — merge por evento, idempotência, preservação de
# hooks alheios. Roda com HOME descartável e PATH sem terminal-notifier.

load helpers

setup() {
  common_setup
  copy_repo
  restrict_path
  SETTINGS="$HOME/.claude/settings.json"
}

teardown() { common_teardown; }

@test "instalacao do zero adiciona os 3 hooks e a skill" {
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hook Notification adicionado"* ]]
  [[ "$output" == *"hook Stop adicionado"* ]]
  [[ "$output" == *"hook PermissionRequest adicionado"* ]]
  for ev in Notification Stop PermissionRequest; do
    [ "$(jq --arg ev "$ev" '.hooks[$ev] | tostring | contains("/skills/notify/")' "$SETTINGS")" = "true" ]
  done
  [ -x "$HOME/.claude/skills/notify/notify.sh" ]
  [ -f "$HOME/.claude/skills/notify/notify-lib.sh" ]
  # O dialog de aprovacao e seu icone precisam viajar junto com a skill.
  [ -f "$HOME/.claude/skills/notify/approval-dialog.js" ]
  [ -f "$HOME/.claude/skills/notify/claude-logo.png" ]
}

@test "re-rodar e idempotente: nada muda e nenhum backup novo" {
  "$WORK/repo/install.sh" >/dev/null
  before="$(cat "$SETTINGS")"
  backups_before="$(find "$HOME/.claude" -name 'settings.json.bak.*' | wc -l)"
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"já configurado"* ]]
  [[ "$output" != *"não vou sobrescrever"* ]]
  [ "$(cat "$SETTINGS")" = "$before" ]
  [ "$(find "$HOME/.claude" -name 'settings.json.bak.*' | wc -l)" = "$backups_before" ]
}

@test "hook alheio e preservado e so os eventos livres sao adicionados" {
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"other-tool.sh"}]}]}}' > "$SETTINGS"
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"não vou sobrescrever"* ]]
  [[ "$output" == *Stop* ]]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" = "other-tool.sh" ]
  [ "$(jq '.hooks.Notification | tostring | contains("/skills/notify/")' "$SETTINGS")" = "true" ]
  [ "$(jq '.hooks.PermissionRequest | tostring | contains("/skills/notify/")' "$SETTINGS")" = "true" ]
}

@test "instalacao que modifica cria backup timestampado" {
  "$WORK/repo/install.sh" >/dev/null
  count="$(find "$HOME/.claude" -name 'settings.json.bak.*' | wc -l | tr -d ' ')"
  [ "$count" = "1" ]
}

@test "uninstall remove o que e nosso e preserva o alheio" {
  "$WORK/repo/install.sh" >/dev/null
  # injeta um hook alheio num evento nosso e um evento que não é nosso
  tmp="$(mktemp)"
  jq '.hooks.Stop += [{"hooks":[{"type":"command","command":"other-tool.sh"}]}]
      | .hooks.PreToolUse = [{"hooks":[{"type":"command","command":"linter.sh"}]}]' \
    "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  run "$WORK/repo/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.claude/skills/notify" ]
  [ "$(jq '.hooks | has("Notification")' "$SETTINGS")" = "false" ]
  [ "$(jq '.hooks | has("PermissionRequest")' "$SETTINGS")" = "false" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" = "other-tool.sh" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS")" = "linter.sh" ]
}

@test "uninstall num sistema limpo nao falha" {
  run "$WORK/repo/uninstall.sh"
  [ "$status" -eq 0 ]
}
