#!/usr/bin/env bats
# check-update.sh — deteccao de versao nova, rate limit e o banner clicavel.
# Nunca toca a rede: o "remoto" e um repo git descartavel local.

load helpers

setup() {
  common_setup
  copy_skill
  stub_notify
  restrict_path
  echo "1.2.0" > "$WORK/skill/VERSION"
  STAMP="$WORK/skill/.update-check"
}

teardown() { common_teardown; }

@test "update: versao maior no remoto gera banner clicavel" {
  remote="$(make_fake_remote v9.9.9)"
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.2.0 -> 9.9.9"* ]]
  calls="$(cat "$WORK/notify.calls")"
  [[ "$calls" == *"Atualização disponível"* ]]
  # O clique precisa disparar o update.sh instalado.
  [[ "$calls" == *"NOTIFY_EXECUTE='$WORK/skill/update.sh'"* ]]
}

@test "update: remoto igual ou mais velho nao notifica" {
  remote="$(make_fake_remote v1.2.0 0.1)"
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"já está atualizado"* ]]
  [ ! -f "$WORK/notify.calls" ]
}

@test "update: tag de duas partes tambem conta" {
  echo "0.0.5" > "$WORK/skill/VERSION"
  remote="$(make_fake_remote 0.1)"
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.0.5 -> 0.1"* ]]
}

@test "update: repo sem tag de versao e reportado sem notificar" {
  remote="$(make_fake_remote naoversao)"
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"nenhuma tag de versão"* ]]
  [ ! -f "$WORK/notify.calls" ]
}

@test "update: rate limit silencia a segunda checagem seguida" {
  remote="$(make_fake_remote v9.9.9)"
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disponível"* ]]
  rm -f "$WORK/notify.calls"

  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "update: --force ignora o rate limit" {
  remote="$(make_fake_remote v9.9.9)"
  NOTIFY_UPDATE_REPO="$remote" "$WORK/skill/check-update.sh" >/dev/null
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"disponível"* ]]
}

@test "update: intervalo vencido volta a checar" {
  remote="$(make_fake_remote v9.9.9)"
  NOTIFY_UPDATE_REPO="$remote" "$WORK/skill/check-update.sh" >/dev/null
  echo "1" > "$STAMP"   # carimbo de 1970
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disponível"* ]]
}

@test "update: carimbo corrompido nao trava a checagem" {
  remote="$(make_fake_remote v9.9.9)"
  echo "lixo" > "$STAMP"
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disponível"* ]]
}

@test "update: NOTIFY_UPDATE_CHECK=0 desliga a checagem automatica" {
  remote="$(make_fake_remote v9.9.9)"
  NOTIFY_UPDATE_CHECK=0 NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$WORK/notify.calls" ]
}

@test "update: sem VERSION instalado, qualquer tag conta como nova" {
  rm -f "$WORK/skill/VERSION"
  remote="$(make_fake_remote v0.2.0)"
  NOTIFY_UPDATE_REPO="$remote" run "$WORK/skill/check-update.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.0.0 -> 0.2.0"* ]]
}

@test "update: remoto inacessivel falha em silencio no modo automatico" {
  NOTIFY_UPDATE_REPO="$WORK/nao-existe" run "$WORK/skill/check-update.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$WORK/notify.calls" ]
}

# ---- update.sh: o clique pergunta antes de instalar --------------------------

setup_update_dialog() {
  stub_osascript
  stub_open
  # Um "clone de origem" cujo install.sh apenas registra que rodou.
  mkdir -p "$WORK/src/.git"
  cat > "$WORK/src/install.sh" <<EOF
#!/bin/bash
echo "instalador rodou" >> "$WORK/installer.calls"
echo "9.9.9" > "$WORK/skill/VERSION"
EOF
  chmod +x "$WORK/src/install.sh"
  printf '%s' "$WORK/src" > "$WORK/skill/.source-repo"
  # git nao deve ser chamado no caminho de dialogo; se for, o pull falha cedo.
  cat > "$STUB/git" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$STUB/git"
}

@test "update: Cancelar nao instala nada" {
  setup_update_dialog
  OSA_RESULT="cancel" run "$WORK/skill/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelada"* ]]
  [ ! -f "$WORK/installer.calls" ]
}

@test "update: Esc/timeout nao instala nada" {
  setup_update_dialog
  OSA_RESULT="" run "$WORK/skill/update.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/installer.calls" ]
}

@test "update: Ver no GitHub abre o navegador e nao instala" {
  setup_update_dialog
  OSA_RESULT="github" run "$WORK/skill/update.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/installer.calls" ]
  [[ "$(cat "$WORK/open.calls")" == *"github.com/hallanneves/claude-notifications/releases"* ]]
}

@test "update: Instalar roda o instalador e avisa a versao nova" {
  setup_update_dialog
  OSA_RESULT="install" run "$WORK/skill/update.sh"
  [ "$status" -eq 0 ]
  [ -f "$WORK/installer.calls" ]
  [[ "$output" == *"1.2.0 para a 9.9.9"* ]]
  [[ "$(cat "$WORK/notify.calls")" == *--done* ]]
}

@test "update: --yes pula o dialogo" {
  setup_update_dialog
  run "$WORK/skill/update.sh" --yes
  [ "$status" -eq 0 ]
  [ -f "$WORK/installer.calls" ]
  [ ! -f "$WORK/osascript.calls" ]
}

@test "update: o dialogo oferece as tres opcoes com atalho" {
  setup_update_dialog
  OSA_RESULT="cancel" run "$WORK/skill/update.sh"
  calls="$(cat "$WORK/osascript.calls")"
  [[ "$calls" == *"Instalar:i:install"* ]]
  [[ "$calls" == *"Ver no GitHub:g:github"* ]]
  [[ "$calls" == *"Cancelar (Esc):esc:cancel"* ]]
}

@test "update: pull que falha vira notificacao de falha, sem instalar" {
  setup_update_dialog
  cat > "$STUB/git" <<'EOF'
#!/bin/bash
[ "$1" = "-C" ] && exit 1
exit 0
EOF
  chmod +x "$STUB/git"
  OSA_RESULT="install" run "$WORK/skill/update.sh"
  [ "$status" -eq 1 ]
  [ ! -f "$WORK/installer.calls" ]
  [[ "$(cat "$WORK/notify.calls")" == *--fail* ]]
}
