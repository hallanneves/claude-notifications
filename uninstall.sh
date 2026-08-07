#!/bin/bash
# Uninstaller: removes the skill, the dedicated notifier app and OUR hook
# entries from ~/.claude/settings.json. Hook entries that belong to other
# tools are preserved untouched.
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=skill/notify-lib.sh
. ./skill/notify-lib.sh
load_notify_conf

SETTINGS="$HOME/.claude/settings.json"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '(.hooks // {}) | tostring | contains("/skills/notify/")' "$SETTINGS" >/dev/null 2>&1; then
    BACKUP="${SETTINGS}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    tmp="$(mktemp)"
    jq '
      def strip($ev):
        if .hooks[$ev] then
          .hooks[$ev] |= map(select(tostring | contains("/skills/notify/") | not))
          | if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end
        else . end;
      strip("Notification") | strip("Stop") | strip("PermissionRequest")
      | if .hooks == {} then del(.hooks) else . end
    ' "$SETTINGS" > "$tmp"
    jq -e . "$tmp" >/dev/null
    mv "$tmp" "$SETTINGS"
    printf '✅ '; say "$L_UNI_HOOKS_REMOVED" "$SETTINGS" "$BACKUP"
  else
    printf 'ℹ️  '; say "$L_UNI_NO_HOOKS" "$SETTINGS"
  fi
fi

# Stop active reminders before their scripts disappear.
if [ -x "$HOME/.claude/skills/notify/repeat.sh" ]; then
  "$HOME/.claude/skills/notify/repeat.sh" stop >/dev/null 2>&1 || true
fi

if [ -d "$HOME/.claude/skills/notify" ]; then
  rm -rf "$HOME/.claude/skills/notify"
  echo "✅ $L_UNI_SKILL_REMOVED"
fi

if [ -d "$DEDICATED_APP" ]; then
  rm -rf "$DEDICATED_APP"
  printf '✅ '; say "$L_UNI_APP_REMOVED" "$DEDICATED_APP_NAME"
fi

echo "ℹ️  $L_UNI_ICON_HINT"
echo "$L_UNI_ICON_HINT2"
echo "➡️  $L_UNI_RESTART"
