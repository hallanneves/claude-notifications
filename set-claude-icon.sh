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
# shellcheck source=skills/notify/notify-lib.sh
. ./skills/notify/notify-lib.sh
load_notify_conf

APP="$(icon_target_bundle)" || {
  echo "❌ $L_APP_NO_TN"
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

# Same icon already in a validly signed bundle: stop here. Every ad-hoc
# re-sign changes the bundle's hash, and macOS may then forget permissions it
# had granted the app (notifications, Automation). The icns build is
# deterministic, so a byte compare is enough.
if cmp -s "$WORK/icon.icns" "$APP/Contents/Resources/$ICNS_NAME" \
  && codesign -v "$APP" >/dev/null 2>&1; then
  printf '✅ '; say "$L_ICON_UNCHANGED" "$APP"
  exit 0
fi

cp "$WORK/icon.icns" "$APP/Contents/Resources/$ICNS_NAME"
# Touching bundle contents invalidates the signature; without re-signing macOS
# treats the app as tampered with.
codesign --force --deep -s - "$APP"
touch "$APP"
"${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}" -f "$APP"
killall NotificationCenter 2>/dev/null || true

printf '✅ '; say "$L_ICON_APPLIED" "$APP"
case "$APP" in
  "$DEDICATED_APP") ;;
  *) echo "$L_ICON_SHARED"
     echo "$L_ICON_SHARED2" ;;
esac
