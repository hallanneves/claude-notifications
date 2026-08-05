#!/bin/bash
# notify.sh — native macOS notification (banner + sound), Slack-style.
# usage: notify.sh [--approval|--info|--done|--fail] MESSAGE [TITLE] [SUBTITLE] [SOUND]
# The type presets an emoji title + a sound that matches the event's feeling;
# explicit TITLE/SOUND arguments override the preset.
set -euo pipefail

TYPE="info"
case "${1:-}" in
  --approval|--info|--done|--fail) TYPE="${1#--}"; shift ;;
esac

MSG="${1:?usage: notify.sh [--approval|--info|--done|--fail] MESSAGE [TITLE] [SUBTITLE] [SOUND]}"
TITLE="${2:-}"
SUBTITLE="${3:-}"
SOUND="${4:-}"

case "$TYPE" in
  approval) : "${TITLE:=Aprovação necessária}"; : "${SOUND:=Submarine}" ;;
  done)     : "${TITLE:=Trabalho concluído}";   : "${SOUND:=Hero}" ;;
  fail)     : "${TITLE:=Algo falhou}";          : "${SOUND:=Basso}" ;;
  info)     : "${TITLE:=Claude Code}";          : "${SOUND:=Glass}" ;;
esac

if command -v terminal-notifier >/dev/null 2>&1; then
  # Clicking the notification focuses the editor instead of macOS's blank
  # Script Editor fallback. Override the target app via NOTIFY_ACTIVATE.
  args=(-message "$MSG" -title "$TITLE" -sound "$SOUND" -activate "${NOTIFY_ACTIVATE:-com.microsoft.VSCode}")
  [ -n "$SUBTITLE" ] && args+=(-subtitle "$SUBTITLE")
  terminal-notifier "${args[@]}"
else
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  script="display notification \"$(esc "$MSG")\" with title \"$(esc "$TITLE")\""
  [ -n "$SUBTITLE" ] && script="$script subtitle \"$(esc "$SUBTITLE")\""
  [ -n "$SOUND" ] && script="$script sound name \"$SOUND\""
  osascript -e "$script"
fi
