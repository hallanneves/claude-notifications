#!/bin/bash
# Swap terminal-notifier's app icon for the Claude logo so notifications are
# instantly identifiable. Re-run after `brew upgrade terminal-notifier` — the
# upgrade restores the stock Terminal icon.
set -euo pipefail
cd "$(dirname "$0")"

command -v terminal-notifier >/dev/null 2>&1 \
  || { echo "❌ terminal-notifier não instalado (brew install terminal-notifier)"; exit 1; }

BIN="$(readlink -f "$(command -v terminal-notifier)")"
APP="${BIN%/Contents/MacOS/*}"
case "$APP" in
  *.app) [ -d "$APP" ] || { echo "❌ bundle não encontrado: $APP"; exit 1; } ;;
  *) echo "❌ não consegui resolver o terminal-notifier.app a partir de $BIN"; exit 1 ;;
esac

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
codesign --force --deep -s - "$APP"
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
killall NotificationCenter 2>/dev/null || true

echo "✅ ícone do Claude aplicado em $APP"
echo "   Re-rode este script depois de um 'brew upgrade terminal-notifier'."
