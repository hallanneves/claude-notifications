#!/usr/bin/env bats
# Selecao de idioma: NOTIFY_LANG, deteccao pelo locale e fallback.

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
  # Sem stub de defaults, a deteccao cai no LANG/LC_* do ambiente de teste.
  unset LANG LC_ALL LC_MESSAGES
}

teardown() { common_teardown; }

resolved() {
  bash -c ". \"$WORK/skill/notify-lib.sh\"; load_notify_conf; printf '%s' \"\$NOTIFY_LANG_RESOLVED\""
}

@test "i18n: NOTIFY_LANG=en produz titulos em ingles" {
  NOTIFY_LANG=en NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "build ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *$'-title\nWork finished'* ]]
}

@test "i18n: NOTIFY_LANG=pt produz titulos em portugues" {
  NOTIFY_LANG=pt NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --done "build ok"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *$'-title\nTrabalho concluído'* ]]
}

@test "i18n: idioma sem catalogo cai no ingles" {
  NOTIFY_LANG=klingon run bash -c "NOTIFY_LANG=klingon; . \"$WORK/skill/notify-lib.sh\"; load_notify_conf; printf '%s|%s' \"\$NOTIFY_LANG_RESOLVED\" \"\$L_TITLE_DONE\""
  [ "$status" -eq 0 ]
  [ "$output" = "en|Work finished" ]
}

@test "i18n: pt_BR do locale resolve para pt" {
  cat > "$STUB/defaults" <<'EOF'
#!/bin/bash
echo "pt_BR"
EOF
  chmod +x "$STUB/defaults"
  NOTIFY_LANG= run resolved
  [ "$output" = "pt" ]
}

@test "i18n: en_BR resolve para en (a regiao nao decide o idioma)" {
  cat > "$STUB/defaults" <<'EOF'
#!/bin/bash
echo "en_BR"
EOF
  chmod +x "$STUB/defaults"
  NOTIFY_LANG= run resolved
  [ "$output" = "en" ]
}

@test "i18n: NOTIFY_LANG vence o locale do sistema" {
  cat > "$STUB/defaults" <<'EOF'
#!/bin/bash
echo "pt_BR"
EOF
  chmod +x "$STUB/defaults"
  NOTIFY_LANG=en run resolved
  [ "$output" = "en" ]
}

@test "i18n: notify.conf define o idioma" {
  mkdir -p "$HOME/.claude/skills/notify"
  echo 'NOTIFY_LANG="en"' > "$HOME/.claude/skills/notify/notify.conf"
  NOTIFY_LANG= NOTIFY_TN="$STUB/tn" run "$WORK/skill/notify.sh" --fail "quebrou"
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK/tn.args")" == *$'-title\nSomething failed'* ]]
}

@test "i18n: sem locale nenhum, o padrao e ingles" {
  cat > "$STUB/defaults" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$STUB/defaults"
  NOTIFY_LANG= run resolved
  [ "$output" = "en" ]
}

@test "i18n: o dialogo de aprovacao usa D para Deny em ingles" {
  stub_notify
  stub_lsappinfo
  stub_osascript
  export NOTIFY_LANG=en NOTIFY_FORCE=1 OSA_RESULT="deny"
  run bash -c 'echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | "$0"' "$WORK/skill/approval-hook.sh"
  [ "$status" -eq 0 ]
  calls="$(cat "$WORK/osascript.calls")"
  [[ "$calls" == *"Approve:a:approve|Deny:d:deny"* ]]
  [[ "$calls" == *"Claude wants to use: Bash"* ]]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.behavior')" = "deny" ]
  [[ "$(echo "$output" | jq -r '.hookSpecificOutput.decision.message')" == *"Denied by"* ]]
}

@test "i18n: catalogos tem exatamente as mesmas chaves" {
  en="$(grep -oE '^L_[A-Z0-9_]+' "$WORK/skill/lang/en.sh" | sort)"
  pt="$(grep -oE '^L_[A-Z0-9_]+' "$WORK/skill/lang/pt.sh" | sort)"
  [ "$en" = "$pt" ]
}

@test "i18n: nenhum L_ usado nos scripts esta faltando nos catalogos" {
  # Toda referencia \$L_FOO precisa existir nos dois catalogos, senao a string
  # sai vazia em producao sem erro nenhum.
  used="$(grep -ohE '\$\{?L_[A-Z0-9_]+' "$WORK/skill"/*.sh | tr -d '${' | sort -u)"
  for key in $used; do
    grep -q "^$key=" "$WORK/skill/lang/en.sh" || { echo "faltando em en.sh: $key"; return 1; }
    grep -q "^$key=" "$WORK/skill/lang/pt.sh" || { echo "faltando em pt.sh: $key"; return 1; }
  done
}
