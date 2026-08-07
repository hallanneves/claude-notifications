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

front_is_editor && exit 0

PROJ="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
PROJ="${PROJ##*/}"
exec "$DIR/notify.sh" --done "Terminei${PROJ:+ em $PROJ} — pode conferir" "" "${PROJ:+projeto $PROJ}"
