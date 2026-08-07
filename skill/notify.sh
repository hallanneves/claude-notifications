#!/bin/bash
# notify.sh — native macOS notification (banner + sound), Slack-style.
# usage: notify.sh [--approval|--info|--done|--fail] MESSAGE [TITLE] [SUBTITLE] [SOUND]
# The type presets a title + a sound that matches the event's feeling; explicit
# TITLE/SOUND arguments override the preset. No emojis in titles or messages.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

TYPE="info"
case "${1:-}" in
  --approval|--info|--done|--fail) TYPE="${1#--}"; shift ;;
esac

MSG="${1:?usage: notify.sh [--approval|--info|--done|--fail] MESSAGE [TITLE] [SUBTITLE] [SOUND]}"
TITLE="${2:-}"
SUBTITLE="${3:-}"
SOUND="${4:-}"

case "$TYPE" in
  approval) : "${TITLE:=$L_TITLE_APPROVAL}"; : "${SOUND:=Submarine}" ;;
  done)     : "${TITLE:=$L_TITLE_DONE}";     : "${SOUND:=Hero}" ;;
  fail)     : "${TITLE:=$L_TITLE_FAIL}";     : "${SOUND:=Basso}" ;;
  info)     : "${TITLE:=$L_TITLE_INFO}";     : "${SOUND:=Glass}" ;;
esac

# An unknown sound name plays nothing, with no error from any notifier — warn
# so a typo doesn't read as "notifications are broken".
if [ -n "$SOUND" ] && [ "$SOUND" != "default" ] \
  && [ ! -f "/System/Library/Sounds/$SOUND.aiff" ] \
  && [ ! -f "/Library/Sounds/$SOUND.aiff" ] \
  && [ ! -f "$HOME/Library/Sounds/$SOUND.aiff" ]; then
  say "$L_WARN_SOUND" "$SOUND" >&2
fi

# Prefer the dedicated copy of the terminal-notifier bundle when one exists:
# with its own bundle id it gets its own entry in System Settings >
# Notifications and carries the Claude icon WITHOUT branding every other
# terminal-notifier caller on this machine. Override with NOTIFY_TN
# (notify.conf or environment).
TN="${NOTIFY_TN:-}"
DEDICATED="$DEDICATED_APP/Contents/MacOS/terminal-notifier"
if [ -z "$TN" ] && [ -x "$DEDICATED" ]; then
  TN="$DEDICATED"
elif [ -z "$TN" ]; then
  TN="$(command -v terminal-notifier 2>/dev/null || true)"
fi

if [ -n "$TN" ]; then
  args=(-message "$MSG" -title "$TITLE" -sound "$SOUND")
  [ -n "$SUBTITLE" ] && args+=(-subtitle "$SUBTITLE")
  if [ -n "${NOTIFY_EXECUTE:-}" ]; then
    # Turns the banner into an action: clicking it runs this command instead
    # of focusing an app. Mutually exclusive with -activate.
    args+=(-execute "$NOTIFY_EXECUTE")
  else
    # Clicking the notification focuses the editor instead of macOS's blank
    # Script Editor fallback. Override the target app via NOTIFY_ACTIVATE
    # (notify.conf or environment).
    args+=(-activate "${NOTIFY_ACTIVATE:-$NOTIFY_ACTIVATE_DEFAULT}")
  fi
  "$TN" "${args[@]}"
else
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  script="display notification \"$(esc "$MSG")\" with title \"$(esc "$TITLE")\""
  [ -n "$SUBTITLE" ] && script="$script subtitle \"$(esc "$SUBTITLE")\""
  [ -n "$SOUND" ] && script="$script sound name \"$SOUND\""
  osascript -e "$script"
fi
