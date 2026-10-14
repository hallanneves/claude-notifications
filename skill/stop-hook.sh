#!/bin/bash
# Stop-hook adapter: "work done" banner when Claude finishes a turn.
# Suppressed while you are looking at it: an editor/terminal in front AND
# someone at the keyboard. Left the editor in front and walked away? It fires.
# Fails open — if the frontmost check errors, it notifies.
# Set NOTIFY_FORCE=1 to bypass the suppression (used for testing).
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

if is_user_watching; then
  debug_log stop "suppressed: user is watching"
  exit 0
fi

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
PROJ="${CWD##*/}"
export NOTIFY_TARGET_PATH="$CWD"
if [ -n "$PROJ" ]; then
  exec "$DIR/notify.sh" --done "$(say "$L_STOP_DONE_IN" "$PROJ")" "" "$(say "$L_STOP_SUBTITLE" "$PROJ")"
fi
exec "$DIR/notify.sh" --done "$L_STOP_DONE"
