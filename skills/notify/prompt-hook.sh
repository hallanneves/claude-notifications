#!/bin/bash
# UserPromptSubmit-hook adapter. You just wrote to this session, so:
#   - its notifications are stale: they leave Notification Center;
#   - the turn clock starts, which lets the Stop hook skip quick replies;
#   - an old "already announced" stamp no longer applies.
# Wired async: it must never delay the prompt.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf
# A pre-2.0 install is still wired: it handles this event (see plugin_yields).
plugin_yields && exit 0

INPUT="$(cat)"
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$SESSION" ] || exit 0

stamp turn "$SESSION"
unstamp announced "$SESSION"

TN="$(notifier_bin || true)"
if [ -n "$TN" ]; then
  "$TN" -remove "$(session_group "$SESSION")" >/dev/null 2>&1 || true
fi

# One small file per session and kind; a week is long enough to keep them.
find "$NOTIFY_STATE_DIR" -maxdepth 1 -type f \
  \( -name '.turn-*' -o -name '.stopped-*' -o -name '.announced-*' \) \
  -mtime +7 -delete 2>/dev/null
exit 0
