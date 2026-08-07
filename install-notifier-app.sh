#!/bin/bash
# Create a dedicated terminal-notifier app bundle for Claude Code notifications.
#
# Why this exists: run terminal-notifier straight out of the Homebrew keg and
# macOS (confirmed on 26.x) never registers it as a notification-capable app.
# It never prompts for permission, accepts every notification — they do show up
# in `terminal-notifier -list ALL` — and drops the banner silently. Every
# command exits 0, no error anywhere, nothing on screen. A bundle with its own
# identity under ~/Applications, launched once, does get the permission prompt.
#
# It also bounds the icon's blast radius: the Claude logo lives in THIS bundle,
# so every other terminal-notifier caller on the machine keeps its own icon and
# `brew upgrade` no longer reverts anything.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=skill/notify-lib.sh
. ./skill/notify-lib.sh

SRC="$(brew_bundle)" || {
  echo "❌ terminal-notifier não encontrado (brew install terminal-notifier)"
  exit 1
}

CREATED=0
if [ -d "$DEDICATED_APP" ] && [ "${1:-}" != "--force" ]; then
  echo "ℹ️  $DEDICATED_APP já existe — mantendo (use --force para recriar)."
  echo "   Recriar zera a autorização: o macOS pergunta de novo."
else
  rm -rf "$DEDICATED_APP"
  mkdir -p "$HOME/Applications"
  cp -R "$SRC" "$DEDICATED_APP"

  PB=/usr/libexec/PlistBuddy
  PLIST="$DEDICATED_APP/Contents/Info.plist"
  # The distinct bundle id is the whole point: it is what earns a separate entry
  # in System Settings > Notifications instead of inheriting terminal-notifier's
  # (which is the identity macOS refuses to register from inside the keg).
  "$PB" -c "Set :CFBundleIdentifier $DEDICATED_BUNDLE_ID" "$PLIST"
  "$PB" -c "Set :CFBundleName Claude Code" "$PLIST"
  "$PB" -c "Set :CFBundleDisplayName Claude Code" "$PLIST" 2>/dev/null \
    || "$PB" -c "Add :CFBundleDisplayName string Claude Code" "$PLIST"
  # Editing the plist invalidates the signature — re-sign before anything runs it.
  codesign --force --deep -s - "$DEDICATED_APP"
  echo "✅ bundle criado em $DEDICATED_APP"
  CREATED=1
fi

# Applies the icon AND re-signs/re-registers the bundle.
./set-claude-icon.sh || echo "⚠️  não consegui aplicar o ícone (rode ./set-claude-icon.sh depois)"

# Registering is not enough: the app has to be LAUNCHED once before macOS will
# offer the notification permission prompt. Only needed for a fresh bundle —
# an existing one already carries its authorization.
if [ "$CREATED" = 1 ]; then
  open "$DEDICATED_APP" 2>/dev/null || true
  sleep 2
  "$DEDICATED_APP/Contents/MacOS/terminal-notifier" \
    -message "Autorize as notificações para receber os avisos do Claude Code" \
    -title "Claude Code" -sound Glass >/dev/null 2>&1 || true

  echo
  echo "➡️  O macOS deve mostrar 'Notificações de \"Claude Code\"' — clique em Permitir."
  echo "   Se não aparecer: Ajustes do Sistema → Notificações → Claude Code → ligue"
  echo "   'Permitir notificações' e deixe o estilo em Banners ou Alertas."
fi
