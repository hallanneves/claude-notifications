#!/usr/bin/env bats
# install-notifier-app.sh e set-claude-icon.sh — o bundle dedicado que posta
# as notificacoes. Bundle e keg sao falsos; PlistBuddy e real (so edita o
# plist descartavel).

load helpers

setup() {
  common_setup
  mkdir -p "$WORK/repo"
  cp "$REPO/install-notifier-app.sh" "$REPO/set-claude-icon.sh" "$WORK/repo/"
  mkdir -p "$WORK/repo/skills" && cp -R "$REPO/skills/notify" "$WORK/repo/skills/notify"
  cp -R "$REPO/assets" "$WORK/repo/assets"

  # O terminal-notifier "do Homebrew": wrapper no bin, bundle no keg.
  KEG="$WORK/keg/terminal-notifier.app"
  mkdir -p "$KEG/Contents/MacOS" "$KEG/Contents/Resources"
  cat > "$KEG/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>fr.julienxx.oss.terminal-notifier</string>
  <key>CFBundleName</key><string>terminal-notifier</string>
  <key>CFBundleIconFile</key><string>Terminal</string>
</dict></plist>
PLIST
  printf '#!/bin/bash\nexit 0\n' > "$KEG/Contents/MacOS/terminal-notifier"
  chmod +x "$KEG/Contents/MacOS/terminal-notifier"
  printf '#!/bin/bash\nexec "%s/Contents/MacOS/terminal-notifier" "$@"\n' "$KEG" > "$STUB/terminal-notifier"

  # Ferramentas que mexeriam no sistema de verdade.
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/codesign.calls"\nexit 0\n' "$WORK" > "$STUB/codesign"
  printf '#!/bin/bash\nwhile [ $# -gt 0 ]; do [ "$1" = "--out" ] && printf png > "$2"; shift; done\n' > "$STUB/sips"
  printf '#!/bin/bash\nwhile [ $# -gt 0 ]; do [ "$1" = "-o" ] && printf icns-fixo > "$2"; shift; done\n' > "$STUB/iconutil"
  printf '#!/bin/bash\nexit 0\n' > "$STUB/killall"
  printf '#!/bin/bash\nexit 0\n' > "$STUB/sleep"
  printf '#!/bin/bash\nexit 0\n' > "$STUB/lsregister"
  chmod +x "$STUB"/*
  stub_open
  export LSREGISTER="$STUB/lsregister"
  restrict_path
  APP="$HOME/Applications/Claude Code Notifier.app"
}

teardown() { common_teardown; }

usage_string() {
  /usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" "$APP/Contents/Info.plist"
}

@test "app: o bundle criado declara o uso de Apple Events" {
  # Sem essa chave o pedido de Automacao (para focar a aba do Terminal no
  # clique) nao tem texto, ou nem chega a aparecer.
  run "$WORK/repo/install-notifier-app.sh"
  [ "$status" -eq 0 ]
  run usage_string
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "app: bundle antigo ganha a chave sem ser recriado" {
  run "$WORK/repo/install-notifier-app.sh"
  /usr/libexec/PlistBuddy -c "Delete :NSAppleEventsUsageDescription" "$APP/Contents/Info.plist" || true
  rm -f "$WORK/open.calls"
  run "$WORK/repo/install-notifier-app.sh"
  [ "$status" -eq 0 ]
  run usage_string
  [ "$status" -eq 0 ]
  # Nao foi recriado: o macOS nao pediu a permissao de notificacao de novo.
  [ ! -f "$WORK/open.calls" ]
}

@test "icone: re-rodar sem mudanca nao re-assina o app" {
  # Cada re-assinatura ad-hoc muda o hash do bundle, e o macOS pode esquecer
  # as permissoes que ja tinha dado a ele.
  run "$WORK/repo/install-notifier-app.sh"
  [ "$status" -eq 0 ]
  before="$(grep -c -- '--force' "$WORK/codesign.calls")"
  run "$WORK/repo/install-notifier-app.sh"
  [ "$status" -eq 0 ]
  run "$WORK/repo/set-claude-icon.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--force' "$WORK/codesign.calls")" -eq "$before" ]
}
