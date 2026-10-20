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

@test "instalacao do zero adiciona os 4 hooks e a skill" {
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hook Notification adicionado"* ]]
  [[ "$output" == *"hook Stop adicionado"* ]]
  [[ "$output" == *"hook PermissionRequest adicionado"* ]]
  [[ "$output" == *"hook UserPromptSubmit adicionado"* ]]
  [ -x "$HOME/.claude/skills/notify/prompt-hook.sh" ]
  [ -x "$HOME/.claude/skills/notify/doctor.sh" ]
  # O UserPromptSubmit nunca pode atrasar o prompt.
  [ "$(jq '.hooks.UserPromptSubmit[0].hooks[0].async' "$SETTINGS")" = "true" ]
  for ev in Notification Stop PermissionRequest UserPromptSubmit; do
    [ "$(jq --arg ev "$ev" '.hooks[$ev] | tostring | contains("/skills/notify/")' "$SETTINGS")" = "true" ]
  done
  [ -x "$HOME/.claude/skills/notify/notify.sh" ]
  [ -f "$HOME/.claude/skills/notify/notify-lib.sh" ]
  # O dialog de aprovacao e seu icone precisam viajar junto com a skill.
  [ -f "$HOME/.claude/skills/notify/dialog.js" ]
  [ -f "$HOME/.claude/skills/notify/claude-logo.png" ]
  [ -f "$HOME/.claude/skills/notify/VERSION" ]
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
  [ "$(jq '.hooks | has("UserPromptSubmit")' "$SETTINGS")" = "false" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" = "other-tool.sh" ]
  # O estado (silencio, lembretes, logs) sai junto.
  [ ! -d "$STATE" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS")" = "linter.sh" ]
}

@test "uninstall num sistema limpo nao falha" {
  run "$WORK/repo/uninstall.sh"
  [ "$status" -eq 0 ]
}

@test "instalacao migra o estado da versao antiga e preserva o silencio" {
  # Ate a 1.7 o estado morava ao lado da skill; reinstalar trocava o diretorio.
  mkdir -p "$HOME/.claude/skills/notify"
  echo forever > "$HOME/.claude/skills/notify/.mute-until"
  echo "123 x" > "$HOME/.claude/skills/notify/.repeat.pids"
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/.mute-until")" = "forever" ]
  [ "$(cat "$STATE/.repeat.pids")" = "123 x" ]
  [ ! -f "$HOME/.claude/skills/notify/.mute-until" ]
  run "$HOME/.claude/skills/notify/mute.sh" status
  [[ "$output" == *"silenciadas"* ]]
}

# code falso: lista FAKE_CODE_LIST e grava instalacoes/remocoes.
stub_code() {
  cat > "$STUB/code" <<STUBEOF
#!/bin/bash
printf '%s\n' "\$*" >> "$WORK/code.calls"
case "\$1" in
  --list-extensions) printf '%s\n' "\${FAKE_CODE_LIST:-}" ;;
  --install-extension) cp "\$2" "$WORK/installed.vsix" ;;
esac
exit 0
STUBEOF
  chmod +x "$STUB/code"
}

@test "instalacao instala a extensao ponte no VSCode" {
  stub_code
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/code.calls")" == *"--install-extension"* ]]
  unzip -Z1 "$WORK/installed.vsix" | grep -qx "extension/extension.js"
  [[ "$output" == *"extensão ponte instalada no code"* ]]
}

@test "reinstalar com a ponte na mesma versao nao reinstala" {
  stub_code
  export FAKE_CODE_LIST="hallanneves.claude-notify-bridge@$(jq -r .version "$REPO/vscode-bridge/package.json")"
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/code.calls")" != *"--install-extension"* ]]
  [[ "$output" == *"extensão ponte já instalada"* ]]
}

@test "NOTIFY_BRIDGE=0 nao instala a ponte" {
  stub_code
  NOTIFY_BRIDGE=0 run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/code.calls" ]
}

@test "uninstall remove a extensao ponte" {
  stub_code
  export FAKE_CODE_LIST="hallanneves.claude-notify-bridge"
  run "$WORK/repo/uninstall.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/code.calls")" == *"--uninstall-extension hallanneves.claude-notify-bridge"* ]]
}
