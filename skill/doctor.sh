#!/bin/bash
# doctor.sh — what the notifications would do for THIS session, and why.
#
# usage: doctor.sh          # read-only report
#        doctor.sh --test   # also posts a banner; click it, and the report
#                           # says what the click actually did
#
# Every hook fails in silence by design, which is right for safety and
# terrible for support. This answers "why did nothing pop?" and "why did the
# click land there?" without reading code.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

detect_origin
HOST="$(host_bundle)"
CWD="$PWD"

say "$L_DOC_TITLE" "$(cat "$DIR/VERSION" 2>/dev/null || echo '?')"
echo

# --- where this session runs, and where a click would land ------------------
case "$ORIGIN_KIND" in
  herdr)            ORIGIN_TEXT="herdr (pane ${HERDR_PANE_ID:-?})" ;;
  tmux)             ORIGIN_TEXT="tmux" ;;
  editor-extension) ORIGIN_TEXT="$(say "$L_DOC_KIND_PANEL" "$ORIGIN_BUNDLE")" ;;
  editor-terminal)  ORIGIN_TEXT="$(say "$L_DOC_KIND_EDITOR_TERM" "$ORIGIN_BUNDLE")" ;;
  app)              ORIGIN_TEXT="$ORIGIN_BUNDLE" ;;
  *)                ORIGIN_TEXT="$L_DOC_UNKNOWN" ;;
esac
say "$L_DOC_ORIGIN" "$ORIGIN_TEXT"
say "$L_DOC_HOST" "${HOST:-$L_DOC_UNKNOWN}"

if [ "$ORIGIN_KIND" = "herdr" ]; then
  CLICK="$(say "$L_DOC_CLICK_HERDR" "${HERDR_PANE_ID:-?}")"
elif [ -n "$(iterm_session)" ]; then
  CLICK="$(say "$L_DOC_CLICK_TAB" "$(iterm_session)" "iTerm2")"
elif [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ] && [ -n "$(current_tty)" ]; then
  CLICK="$(say "$L_DOC_CLICK_TAB" "$(current_tty)" "Terminal")"
elif [ -n "$HOST" ] && is_editor_bundle "$HOST" && ROOT="$(editor_root "$CWD")"; then
  CLICK="$(say "$L_DOC_CLICK_WINDOW" "$ROOT")"
elif [ -n "$HOST" ]; then
  CLICK="$(say "$L_DOC_CLICK_APP" "$HOST")"
else
  CLICK="$L_DOC_CLICK_NONE"
fi
say "$L_DOC_CLICK" "$CLICK"

# --- the attention gate, right now -----------------------------------------
WHY="$(say "$L_DOC_REASON_FRONT" "$(front_name)" "$(session_app)"), $(say "$L_DOC_REASON_IDLE" "$(idle_secs)")"
if [ "$ORIGIN_KIND" = "herdr" ]; then
  if herdr_pane_focused; then PANE="$L_DOC_YES"; else PANE="$L_DOC_NO"; fi
  WHY="$WHY, $(say "$L_DOC_REASON_PANE" "$PANE")"
fi
if is_user_watching; then say "$L_DOC_WATCHING_YES" "$WHY"; else say "$L_DOC_WATCHING_NO" "$WHY"; fi

UNTIL="$(mute_until)"
case "$UNTIL" in
  '')      say "$L_DOC_MUTE" "$L_MUTE_OFF" ;;
  forever) say "$L_DOC_MUTE" "$L_MUTE_ON_FOREVER" ;;
  *)       say "$L_DOC_MUTE" "$(say "$L_MUTE_ON_UNTIL" "$(date -r "$UNTIL" '+%H:%M')" | tr -d '\n')" ;;
esac

# --- the notifier ------------------------------------------------------------
TN="$(notifier_bin || true)"
if [ -z "$TN" ]; then
  echo "$L_DOC_NOTIFIER_NONE"
elif [ "$TN" = "$DEDICATED_APP/Contents/MacOS/terminal-notifier" ]; then
  if ! codesign -v "$DEDICATED_APP" >/dev/null 2>&1; then
    say "$L_DOC_NOTIFIER" "$L_DOC_APP_BAD"
  elif ! /usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" \
         "$DEDICATED_APP/Contents/Info.plist" >/dev/null 2>&1; then
    say "$L_DOC_NOTIFIER" "$L_DOC_APP_NO_USAGE"
  else
    say "$L_DOC_NOTIFIER" "$L_DOC_APP_OK"
  fi
else
  say "$L_DOC_NOTIFIER" "$TN"
fi
say "$L_DOC_STATE" "$NOTIFY_STATE_DIR"

# --- things worth fixing -----------------------------------------------------
for mark in "$NOTIFY_STATE_DIR"/.tcc-hint-*; do
  [ -f "$mark" ] || continue
  echo
  say "$L_DOC_TCC_DENIED" "${mark##*/.tcc-hint-}"
done

# herdr plays its own sound when an agent in a background workspace changes
# state (on by default), so a finished turn there sounds twice.
if [ "$ORIGIN_KIND" = "herdr" ]; then
  HERDR_CONF="$HOME/.config/herdr/config.toml"
  if ! awk '/^\[/ { s = $0 } s == "[ui.sound]" && /^[[:space:]]*enabled[[:space:]]*=[[:space:]]*false/ { off = 1 }
            END { exit !off }' "$HERDR_CONF" 2>/dev/null; then
    echo
    say "$L_DOC_HERDR_SOUND" "$HERDR_CONF"
  fi
fi

[ "${1:-}" = "--test" ] || exit 0

# --- a real click ------------------------------------------------------------
REPORT="$(mktemp)"
trap 'rm -f "$REPORT"' EXIT
build_focus_args "$CWD"
CMD="$(shq "$DIR/focus.sh")"
for a in "${FOCUS_ARGS[@]}" --report "$REPORT"; do
  CMD="$CMD $(shq "$a")"
done
echo
echo "$L_DOC_TEST_POSTED"
NOTIFY_EXECUTE="$CMD" "$DIR/notify.sh" --info "$L_DOC_TEST_BANNER" >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
  if [ -s "$REPORT" ]; then
    sleep 1
    while IFS= read -r step; do say "$L_DOC_TEST_RESULT" "$step"; done < "$REPORT"
    exit 0
  fi
  sleep 1
done
echo "$L_DOC_TEST_NONE"
