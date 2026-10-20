#!/usr/bin/env bats
# dialog.js — o que a janela de aprovacao mostra e quais teclas ela aceita.
# Roda o JXA de verdade, sem abrir janela: os modos --visible e
# --parse-buttons existem exatamente para isso.

load helpers

setup() {
  common_setup
  copy_skill
  # Sem os modos de teste, o dialog.js trataria os argumentos como um dialogo
  # de verdade e abriria uma janela modal na tela de quem roda a suite.
  grep -q -- "--visible" "$WORK/skill/dialog.js" && grep -q -- "--parse-buttons" "$WORK/skill/dialog.js" || {
    echo "dialog.js sem modo de teste: rodar abriria janelas reais" >&2
    return 1
  }
}

teardown() { common_teardown; }

jxa() { /usr/bin/osascript -l JavaScript "$WORK/skill/dialog.js" "$@"; }

@test "dialog: bidi e caracteres de controle aparecem visiveis" {
  # U+202E inverte o que vem depois; ESC apaga a tela num terminal. Os dois
  # fariam quem aprova ler outra coisa.
  run jxa --visible $'ls \xe2\x80\xaeexe.txt\x1b[2J'
  [ "$status" -eq 0 ]
  [[ "$output" == *"U+202E"* ]]
  [[ "$output" == *"U+001B"* ]]
  [[ "$output" != *$'\xe2\x80\xae'* ]]
  [[ "$output" != *$'\x1b'* ]]
}

@test "dialog: caracteres de largura zero tambem aparecem" {
  run jxa --visible $'rm\xe2\x80\x8b -rf\xe2\x80\x8f x'
  [ "$status" -eq 0 ]
  [[ "$output" == *"U+200B"* ]]
  [[ "$output" == *"U+200F"* ]]
}

@test "dialog: texto comum, quebra de linha e tab passam intactos" {
  input=$'printf "%s\\n" C:\\dir \'aspas\'\n\tsegunda linha'
  run jxa --visible "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "$input" ]
}

@test "dialog: botao sem tecla nao ganha atalho nem sublinhado" {
  run jxa --parse-buttons "Aprovar::approve|Negar:n:deny|Fechar (Esc):esc:ignore"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[0].keyEquivalent')" = "" ]
  [ "$(echo "$output" | jq -r '.[0].underlineAt')" = "-1" ]
  [ "$(echo "$output" | jq -r '.[1].keyEquivalent')" = "n" ]
  [ "$(echo "$output" | jq -r '.[1].underlineAt')" = "0" ]
}

@test "dialog: nenhum idioma da atalho de teclado ao Aprovar" {
  for lang in "$WORK"/skill/lang/*.sh; do
    spec="$(bash -c ". \"$lang\"; printf '%s' \"\$L_APPROVAL_BUTTONS\"")"
    run jxa --parse-buttons "$spec"
    [ "$status" -eq 0 ]
    key="$(echo "$output" | jq -r '.[] | select(.token == "approve") | .keyEquivalent')"
    [ "$key" = "" ] || { echo "$lang da atalho '$key' ao Aprovar"; return 1; }
  done
}

@test "dialog: rotulo com dois-pontos (regra do Aprovar sempre) nao quebra os botoes" {
  run jxa --parse-buttons "Aprovar::approve|Aprovar sempre: Bash(npm test:*)::always|Negar:n:deny"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[1].label')" = "Aprovar sempre: Bash(npm test:*)" ]
  [ "$(echo "$output" | jq -r '.[1].token')" = "always" ]
  [ "$(echo "$output" | jq -r '.[1].keyEquivalent')" = "" ]
  [ "$(echo "$output" | jq -r '.[2].token')" = "deny" ]
}
