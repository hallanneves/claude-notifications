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
load_notify_conf

SRC="$(brew_bundle)" || {
  echo "❌ $L_APP_NO_TN"
  exit 1
}

CREATED=0
if [ -d "$DEDICATED_APP" ] && [ "${1:-}" != "--force" ]; then
  printf 'ℹ️  '; say "$L_APP_EXISTS" "$DEDICATED_APP"
  echo "$L_APP_EXISTS2"
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
  printf '✅ '; say "$L_APP_CREATED" "$DEDICATED_APP"
  CREATED=1
fi

# Applies the icon AND re-signs/re-registers the bundle.
./set-claude-icon.sh || echo "⚠️  $L_APP_ICON_FAIL"

# Registering is not enough: the app has to be LAUNCHED once before macOS will
# offer the notification permission prompt. Only needed for a fresh bundle —
# an existing one already carries its authorization.
if [ "$CREATED" = 1 ]; then
  open "$DEDICATED_APP" 2>/dev/null || true
  sleep 2
  "$DEDICATED_APP/Contents/MacOS/terminal-notifier" \
    -message "$L_APP_AUTHORIZE" \
    -title "Claude Code" -sound Glass >/dev/null 2>&1 || true

  echo
  echo "➡️  $L_APP_ALLOW"
  echo "$L_APP_ALLOW2"
  echo "$L_APP_ALLOW3"
fi
