#!/bin/bash
# notify.sh — native macOS notification (banner + sound), Slack-style.
# usage: notify.sh [--approval|--info|--done|--fail] MESSAGE [TITLE] [SUBTITLE] [SOUND]
# The type presets a title + a sound that matches the event's feeling; explicit
# TITLE/SOUND arguments override the preset. No emojis in titles or messages.
set -euo pipefail

CONF="$HOME/.claude/skills/notify/notify.conf"
[ -f "$CONF" ] && . "$CONF"

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

# Prefer a dedicated copy of the terminal-notifier bundle when one exists: with
# its own bundle id it gets its own entry in System Settings > Notifications and
# carries the Claude icon WITHOUT branding every other terminal-notifier caller
# on this machine. Override with NOTIFY_TN (notify.conf or environment).
TN="${NOTIFY_TN:-}"
DEDICATED="$HOME/Applications/Claude Code Notifier.app/Contents/MacOS/terminal-notifier"
if [ -z "$TN" ] && [ -x "$DEDICATED" ]; then
  TN="$DEDICATED"
elif [ -z "$TN" ]; then
  TN="$(command -v terminal-notifier 2>/dev/null || true)"
fi

if [ -n "$TN" ]; then
  # Clicking the notification focuses the editor instead of macOS's blank
  # Script Editor fallback. Override the target app via NOTIFY_ACTIVATE
  # (notify.conf or environment).
  args=(-message "$MSG" -title "$TITLE" -sound "$SOUND" -activate "${NOTIFY_ACTIVATE:-com.microsoft.VSCode}")
  [ -n "$SUBTITLE" ] && args+=(-subtitle "$SUBTITLE")
  "$TN" "${args[@]}"
else
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  script="display notification \"$(esc "$MSG")\" with title \"$(esc "$TITLE")\""
  [ -n "$SUBTITLE" ] && script="$script subtitle \"$(esc "$SUBTITLE")\""
  [ -n "$SOUND" ] && script="$script sound name \"$SOUND\""
  osascript -e "$script"
fi
