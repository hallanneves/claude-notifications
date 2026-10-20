#!/usr/bin/env bats
# doctor.sh — o que as notificacoes fariam por esta sessao, e por que.
# Sem --test ele so le: nenhum banner, nenhuma janela.

load helpers

setup() {
  common_setup
  copy_skill
  stub_lsappinfo
  restrict_path
  TERMINAL="$(fake_app Terminal com.apple.Terminal)"
  export NOTIFY_PID=100
}

teardown() { common_teardown; }

@test "doctor: sessao no herdr mostra o pane, o clique e a dica do som duplo" {
  fake_ps "100 90 ttys005 /bin/bash" "90 70 ttys005 claude" "70 1 ?? /opt/homebrew/bin/herdr" \
    "200 1 ?? $TERMINAL" "210 200 ttys000 login" "230 210 ttys000 herdr"
  export HERDR_PANE_ID="w3:p1" FAKE_FRONT="Terminal" FAKE_HERDR_GET='{"result":{"agent":{"focused":false}}}'
  run "$WORK/skill/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"herdr (pane w3:p1)"* ]]
  [[ "$output" == *"pane w3:p1 do herdr"* ]]
  [[ "$output" == *"pane focado no herdr: não"* ]]
  [[ "$output" == *"o som do herdr está ligado"* ]]
}

@test "doctor: com o som do herdr desligado nao sugere nada" {
  fake_ps "100 90 ttys005 /bin/bash" "90 70 ttys005 claude" "70 1 ?? /opt/homebrew/bin/herdr"
  mkdir -p "$HOME/.config/herdr"
  printf '[ui.sound]\nenabled = false\n' > "$HOME/.config/herdr/config.toml"
  run "$WORK/skill/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"o som do herdr está ligado"* ]]
}

@test "doctor: VSCode na frente com a sessao no Terminal diz que voce nao esta olhando" {
  fake_ps "100 90 ttys004 /bin/bash" "90 80 ttys004 claude" "80 60 ttys004 login" "60 1 ?? $TERMINAL"
  export FAKE_FRONT="Code" TERM_PROGRAM="Apple_Terminal" NOTIFY_TTY="/dev/ttys004"
  run "$WORK/skill/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"aba /dev/ttys004 do Terminal"* ]]
  [[ "$output" == *"você está olhando:  não"* ]]
  [[ "$output" == *"a sessão está no com.apple.Terminal"* ]]
}

@test "doctor: host desconhecido sugere NOTIFY_ACTIVATE" {
  run "$WORK/skill/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOTIFY_ACTIVATE"* ]]
}

@test "doctor: Automacao negada antes aparece com o caminho para permitir" {
  mkdir -p "$STATE"
  : > "$STATE/.tcc-hint-Terminal"
  run "$WORK/skill/doctor.sh"
  [[ "$output" == *"negou acesso ao Terminal"* ]]
}

@test "doctor: plugin instalado mostra de onde veio e o auto-update desligado" {
  fake_ps "100 1 ttys005 /bin/bash"
  mkdir -p "$HOME/.claude/plugins"
  echo '{"version":2,"plugins":{"notify@claude-notifications":[{"scope":"user"}]}}' \
    > "$HOME/.claude/plugins/installed_plugins.json"
  echo '{"claude-notifications":{"source":{"source":"github","repo":"hallanneves/claude-notifications"}}}' \
    > "$HOME/.claude/plugins/known_marketplaces.json"
  run "$WORK/skill/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"notify@claude-notifications de hallanneves/claude-notifications"* ]]
  [[ "$output" == *"Enable auto-update"* ]]
}

@test "doctor: sem o plugin, diz como instalar" {
  fake_ps "100 1 ttys005 /bin/bash"
  run "$WORK/skill/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"não instalado (/plugin install notify"* ]]
}

@test "doctor: instalacao antiga ligada manda rodar /notify migrate" {
  fake_ps "100 1 ttys005 /bin/bash"
  make_legacy_install
  run "$WORK/skill/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/notify migrate"* ]]
}
