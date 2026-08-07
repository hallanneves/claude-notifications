#!/bin/bash
# Swap the notifier app's icon for the Claude logo so notifications are
# instantly identifiable.
#
# Target: the dedicated bundle from install-notifier-app.sh when it exists —
# which keeps the Claude logo off every other terminal-notifier caller on the
# machine and survives `brew upgrade`. Falls back to Homebrew's own
# terminal-notifier.app, in which case a `brew upgrade terminal-notifier`
# restores the stock icon and this script has to be re-run.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=skill/notify-lib.sh
. ./skill/notify-lib.sh

APP="$(icon_target_bundle)" || {
  echo "❌ terminal-notifier não instalado (brew install terminal-notifier)"
  exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/claude.iconset"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" assets/claude-logo.png --out "$WORK/claude.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z "$((s * 2))" "$((s * 2))" assets/claude-logo.png --out "$WORK/claude.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/claude.iconset" -o "$WORK/icon.icns"

ICNS_NAME="$(defaults read "$APP/Contents/Info" CFBundleIconFile 2>/dev/null || echo Terminal)"
ICNS_NAME="${ICNS_NAME%.icns}.icns"
cp "$WORK/icon.icns" "$APP/Contents/Resources/$ICNS_NAME"
# Touching bundle contents invalidates the signature; without re-signing macOS
# treats the app as tampered with.
codesign --force --deep -s - "$APP"
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
killall NotificationCenter 2>/dev/null || true

echo "✅ ícone do Claude aplicado em $APP"
case "$APP" in
  "$DEDICATED_APP") ;;
  *) echo "   Este é o terminal-notifier compartilhado: re-rode após um 'brew upgrade'."
     echo "   Para isolar o ícone só nas notificações do Claude: ./install-notifier-app.sh" ;;
esac
