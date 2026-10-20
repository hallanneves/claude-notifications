#!/bin/bash
# Stop-hook adapter: "work done" banner when Claude finishes a turn.
# Suppressed while you are looking at this session (an editor/terminal in
# front, someone at the keyboard and, under herdr, this pane on screen), and
# for turns shorter than NOTIFY_MIN_TURN_SECS: a quick reply is not worth a
# sound. Fails open — if the frontmost check errors, it notifies.
# Set NOTIFY_FORCE=1 to bypass the attention gate (used for testing).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

INPUT="$(cat)"

# Detached and rate-limited to once a day: it must never delay the turn, and
# it runs before the foreground gate so an update is announced even while you
# are looking at the editor.
( "$DIR/check-update.sh" >/dev/null 2>&1 & ) 2>/dev/null

SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
PROJ="${CWD##*/}"

detect_origin
if is_user_watching; then
  debug_log stop "suppressed: user is watching"
  exit 0
fi

# The clock starts in prompt-hook.sh. No stamp (older install, or a turn not
# started by a prompt) counts as long.
TURN="$(stamp_age turn "$SESSION")"
if [ -n "$TURN" ] && [ "$TURN" -lt "${NOTIFY_MIN_TURN_SECS:-30}" ]; then
  debug_log stop "suppressed: short turn (${TURN}s)"
  exit 0
fi

# What Claude actually said, not "finished — take a look". NOTIFY_PREVIEW=off
# keeps it off the banner (and so off the lock screen).
BODY=""
if [ "${NOTIFY_PREVIEW:-on}" != "off" ]; then
  BODY="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null | first_line)"
fi
if [ -z "$BODY" ]; then
  if [ -n "$PROJ" ]; then BODY="$(say "$L_STOP_DONE_IN" "$PROJ")"; else BODY="$L_STOP_DONE"; fi
fi

# Title: which project. Subtitle: which branch, and what the session is about
# when herdr knows its title. macOS already prints "Claude Code" above both.
if [ -n "$PROJ" ]; then TITLE="$(say "$L_TITLE_DONE_IN" "$PROJ")"; else TITLE="$L_TITLE_DONE"; fi
SUB=""
if [ -n "$CWD" ]; then
  SUB="$(git -C "$CWD" branch --show-current 2>/dev/null || true)"
fi
SESSION_TITLE="$(herdr_session_title)"
if [ -n "$SESSION_TITLE" ]; then
  SUB="${SUB:+$SUB · }$SESSION_TITLE"
fi

stamp stopped "$SESSION"
export NOTIFY_TARGET_PATH="$CWD" NOTIFY_SESSION="$SESSION"
if [ -n "$SESSION" ]; then
  NOTIFY_GROUP="$(session_group "$SESSION")"
  export NOTIFY_GROUP
fi
# Glass, not Hero: the fanfare is for a job you asked to hear about, and a
# fanfare on every turn stops meaning anything.
exec "$DIR/notify.sh" --done "$BODY" "$TITLE" "$SUB" "${NOTIFY_SOUND_TURN:-Glass}"
