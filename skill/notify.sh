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

# Focused work wins over every banner, including the update one.
is_muted && exit 0

MSG="${1:?usage: notify.sh [--approval|--info|--done|--fail] MESSAGE [TITLE] [SUBTITLE] [SOUND]}"
TITLE="${2:-}"
SUBTITLE="${3:-}"
SOUND="${4:-}"

# Each preset's sound can be changed (NOTIFY_SOUND_APPROVAL, _DONE, _FAIL,
# _INFO), but keep the meaning: Hero is success only, Basso failure only.
case "$TYPE" in
  approval) : "${TITLE:=$L_TITLE_APPROVAL}"; : "${SOUND:=${NOTIFY_SOUND_APPROVAL:-Submarine}}" ;;
  done)     : "${TITLE:=$L_TITLE_DONE}";     : "${SOUND:=${NOTIFY_SOUND_DONE:-Hero}}" ;;
  fail)     : "${TITLE:=$L_TITLE_FAIL}";     : "${SOUND:=${NOTIFY_SOUND_FAIL:-Basso}}" ;;
  info)     : "${TITLE:=$L_TITLE_INFO}";     : "${SOUND:=${NOTIFY_SOUND_INFO:-Glass}}" ;;
esac

# "none" is the way to ask for silence: an empty sound falls back to the
# preset above.
[ "$SOUND" = "none" ] && SOUND=""

# An unknown sound name plays nothing, with no error from any notifier — warn
# so a typo doesn't read as "notifications are broken".
if [ -n "$SOUND" ] && [ "$SOUND" != "default" ] \
  && [ ! -f "/System/Library/Sounds/$SOUND.aiff" ] \
  && [ ! -f "/Library/Sounds/$SOUND.aiff" ] \
  && [ ! -f "$HOME/Library/Sounds/$SOUND.aiff" ]; then
  say "$L_WARN_SOUND" "$SOUND" >&2
fi

# The dedicated copy of terminal-notifier when it exists: with its own bundle
# id it gets its own entry in System Settings > Notifications and carries the
# Claude icon WITHOUT branding every other terminal-notifier caller on this
# machine. NOTIFY_TN (notify.conf or environment) overrides.
TN="$(notifier_bin || true)"

if [ -n "$TN" ]; then
  # Once, here: every helper below runs in a subshell and reuses it.
  detect_origin
  args=(-message "$MSG" -title "$TITLE")
  [ -n "$SOUND" ] && args+=(-sound "$SOUND")
  [ -n "$SUBTITLE" ] && args+=(-subtitle "$SUBTITLE")
  # One live notification per Claude session (the hooks set it): a new one
  # replaces the last, and answering the session clears it.
  [ -n "${NOTIFY_GROUP:-}" ] && args+=(-group "$NOTIFY_GROUP")
  if [ -n "${NOTIFY_EXECUTE:-}" ]; then
    # Turns the banner into an action: clicking it runs this command instead
    # of focusing an app. Mutually exclusive with -activate.
    args+=(-execute "$NOTIFY_EXECUTE")
  elif has_focus_target "${NOTIFY_TARGET_PATH:-}"; then
    # -activate only takes a bundle id, so landing on the exact terminal tab
    # (or the right project window) has to go through -execute.
    args+=(-execute "$(focus_cmd "${NOTIFY_TARGET_PATH:-}")")
  else
    # Clicking brings back the app hosting this session instead of macOS's
    # blank Script Editor fallback, and never some other app: with no clue
    # about the host, a click just dismisses. NOTIFY_ACTIVATE (notify.conf or
    # environment) overrides.
    bundle="$(host_bundle)"
    if [ -n "$bundle" ]; then
      args+=(-activate "$bundle")
    fi
  fi
  "$TN" "${args[@]}"
else
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  script="display notification \"$(esc "$MSG")\" with title \"$(esc "$TITLE")\""
  [ -n "$SUBTITLE" ] && script="$script subtitle \"$(esc "$SUBTITLE")\""
  [ -n "$SOUND" ] && script="$script sound name \"$SOUND\""
  osascript -e "$script"
fi
