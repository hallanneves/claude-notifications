#!/bin/bash
# Uninstaller: removes the skill, the dedicated notifier app and OUR hook
# entries from ~/.claude/settings.json. Hook entries that belong to other
# tools are preserved untouched.
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=skill/notify-lib.sh
. ./skill/notify-lib.sh

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
    echo "✅ hooks removidos de $SETTINGS (backup: $BACKUP)"
  else
    echo "ℹ️  nenhum hook da skill em $SETTINGS — nada a remover"
  fi
fi

# Stop active reminders before their scripts disappear.
if [ -x "$HOME/.claude/skills/notify/repeat.sh" ]; then
  "$HOME/.claude/skills/notify/repeat.sh" stop >/dev/null 2>&1 || true
fi

if [ -d "$HOME/.claude/skills/notify" ]; then
  rm -rf "$HOME/.claude/skills/notify"
  echo "✅ skill removida de ~/.claude/skills/notify"
fi

if [ -d "$DEDICATED_APP" ]; then
  rm -rf "$DEDICATED_APP"
  echo "✅ app '$DEDICATED_APP_NAME' removido de ~/Applications"
fi

echo "ℹ️  Se você tinha aplicado o ícone no terminal-notifier compartilhado do Homebrew:"
echo "    brew reinstall terminal-notifier   # restaura o ícone original"
echo "➡️  Reinicie o Claude Code para descarregar os hooks."
