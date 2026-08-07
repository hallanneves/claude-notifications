#!/bin/bash
# Stop-hook adapter: "work done" banner when Claude finishes a turn.
# Suppressed while an editor/terminal is the frontmost app (you can already see
# the result there); fails open — if the frontmost check errors, it notifies.
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

front_is_editor && exit 0

PROJ="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
PROJ="${PROJ##*/}"
if [ -n "$PROJ" ]; then
  exec "$DIR/notify.sh" --done "$(say "$L_STOP_DONE_IN" "$PROJ")" "" "$(say "$L_STOP_SUBTITLE" "$PROJ")"
fi
exec "$DIR/notify.sh" --done "$L_STOP_DONE"
