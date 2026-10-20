#!/usr/bin/env bats
# install.sh / setup.sh / uninstall.sh — o plugin entra pelo CLI do Claude
# Code, a instalacao antiga sai so depois disso, e o que fica fora do Claude
# Code (app de notificacao, extensao ponte) e preparado uma vez por versao.
# HOME descartavel, PATH sem terminal-notifier e um `claude` falso.

load helpers

setup() {
  common_setup
  copy_repo
  restrict_path
  stub_claude
  stub_osascript
  SETTINGS="$HOME/.claude/settings.json"
}

teardown() { common_teardown; }

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

@test "install: instala o plugin do GitHub pelo CLI do Claude Code" {
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$WORK/claude.calls")" = "plugin install notify --marketplace hallanneves/claude-notifications --scope user" ]
  [[ "$output" == *"plugin notify@claude-notifications instalado"* ]]
  # A versao preparada fica registrada: a primeira sessao nao refaz nada.
  [ "$(cat "$STATE/.setup-version")" = "$(cat "$WORK/repo/VERSION")" ]
}

@test "install: --local instala a partir deste checkout" {
  run "$WORK/repo/install.sh" --local
  [ "$status" -eq 0 ]
  [[ "$(head -1 "$WORK/claude.calls")" == *"--marketplace $WORK/repo "* ]]
}

@test "install: sem o CLI do Claude Code, falha e nao mexe na instalacao antiga" {
  make_legacy_install
  before="$(cat "$SETTINGS")"
  NOTIFY_CLAUDE="$WORK/nao-existe" run "$WORK/repo/install.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/plugin install notify --marketplace hallanneves/claude-notifications"* ]]
  [ "$(cat "$SETTINGS")" = "$before" ]
  [ -d "$HOME/.claude/skills/notify" ]
}

@test "install: se o plugin nao instala, a instalacao antiga segue intacta" {
  make_legacy_install
  before="$(cat "$SETTINGS")"
  FAKE_CLAUDE_FAIL=1 run "$WORK/repo/install.sh"
  [ "$status" -eq 1 ]
  [ "$(cat "$SETTINGS")" = "$before" ]
  [ -d "$HOME/.claude/skills/notify" ]
}

@test "install: por cima de uma 1.x, migra preservando hooks alheios e o silencio" {
  make_legacy_install
  echo forever > "$HOME/.claude/skills/notify/.mute-until"
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks | tostring | contains(".claude/skills/notify/")' "$SETTINGS")" = "false" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" = "other-tool.sh" ]
  [ ! -d "$HOME/.claude/skills/notify" ]
  [ "$(cat "$STATE/.mute-until")" = "forever" ]
}

@test "install: rodar de novo nao quebra nada" {
  "$WORK/repo/install.sh" >/dev/null
  run "$WORK/repo/install.sh"
  [ "$status" -eq 0 ]
}

@test "setup: instala a extensao ponte no VSCode" {
  stub_code
  run "$WORK/repo/skills/notify/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/code.calls")" == *"--install-extension"* ]]
  unzip -Z1 "$WORK/installed.vsix" | grep -qx "extension/extension.js"
  [[ "$output" == *"extensão ponte instalada no code"* ]]
}

@test "setup: acha o code fora do PATH do launchd, como no clique da 1.x" {
  # O aviso de atualizacao da 1.x roda o install.sh a partir de um clique, com
  # o PATH minimo do launchd: sem isso a ponte e o app ficariam para tras.
  mkdir -p "$WORK/brew"
  stub_code
  mv "$STUB/code" "$WORK/brew/code"
  NOTIFY_EXTRA_PATH=":$WORK/brew" run "$WORK/repo/skills/notify/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/code.calls")" == *"--install-extension"* ]]
}

@test "setup: com a ponte na mesma versao, nao reinstala" {
  stub_code
  export FAKE_CODE_LIST="hallanneves.claude-notify-bridge@$(jq -r .version "$REPO/vscode-bridge/package.json")"
  run "$WORK/repo/skills/notify/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/code.calls")" != *"--install-extension"* ]]
  [[ "$output" == *"extensão ponte já instalada"* ]]
}

@test "setup: NOTIFY_BRIDGE=0 nao instala a ponte" {
  stub_code
  NOTIFY_BRIDGE=0 run "$WORK/repo/skills/notify/setup.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/code.calls" ]
}

@test "setup: outro setup rodando agora faz este sair sem mexer em nada" {
  stub_code
  mkdir -p "$STATE/.setup.lock"
  run "$WORK/repo/skills/notify/setup.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/code.calls" ]
  [ ! -f "$STATE/.setup-version" ]
}

@test "uninstall: remove o plugin, o que sobrou da 1.x e preserva o alheio" {
  stub_code
  export FAKE_CODE_LIST="hallanneves.claude-notify-bridge"
  "$WORK/repo/install.sh" >/dev/null
  make_legacy_install
  run "$WORK/repo/uninstall.sh"
  [ "$status" -eq 0 ]
  grep -qx "plugin uninstall notify@claude-notifications -y" "$WORK/claude.calls"
  grep -qx "plugin marketplace remove claude-notifications" "$WORK/claude.calls"
  [ "$(jq '.hooks | tostring | contains(".claude/skills/notify/")' "$SETTINGS")" = "false" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" = "other-tool.sh" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS")" = "linter.sh" ]
  [ ! -d "$HOME/.claude/skills/notify" ]
  [ ! -d "$STATE" ]
  [[ "$(cat "$WORK/code.calls")" == *"--uninstall-extension hallanneves.claude-notify-bridge"* ]]
}

@test "uninstall: sistema limpo nao falha" {
  run "$WORK/repo/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/claude.calls" ] || ! grep -q uninstall "$WORK/claude.calls"
}
