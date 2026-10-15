#!/bin/bash
# Notification-hook adapter: reads Claude Code's hook JSON from stdin and fires
# a native macOS banner via notify.sh. Wired in ~/.claude/settings.json (hooks.Notification).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

INPUT="$(cat)"
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
TYPE="$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)"
MSG="$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)"
[ -z "$MSG" ] && MSG="$L_NEEDS_YOU"

# notification_type is the machine-readable field; the message keywords are a
# fallback for Claude Code versions that predate it.
if [ -z "$TYPE" ]; then
  case "$MSG" in
    *permission*|*permissão*|*approval*) TYPE="permission_prompt" ;;
    *waiting*|*input*|*esperando*)       TYPE="idle_prompt" ;;
  esac
fi

debug_log notification "type=${TYPE:-<none>} msg=${MSG:0:60}"

# So a click lands on the session that raised it, and every banner of one
# session replaces the last instead of piling up.
NOTIFY_TARGET_PATH="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
NOTIFY_SESSION="$SESSION"
export NOTIFY_TARGET_PATH NOTIFY_SESSION
if [ -n "$SESSION" ]; then
  NOTIFY_GROUP="$(session_group "$SESSION")"
  export NOTIFY_GROUP
fi
PROJ="${NOTIFY_TARGET_PATH##*/}"

case "$TYPE" in
  permission_prompt)
    # A permission prompt raises BOTH this event (after ~6s of waiting) and
    # PermissionRequest. When approval-hook.sh announced this session's
    # request (banner + dialog) it left a stamp: notifying again would mean
    # two banners and two sonar sounds for one request. When it did NOT —
    # say you were in front of the editor and then walked away — this is the
    # only voice the request has, so it must speak.
    if stamped_within announced "$SESSION" "$(( ${NOTIFY_DIALOG_TIMEOUT:-50} + 30 ))"; then
      exit 0
    fi
    exec "$DIR/notify.sh" --approval "$MSG" "" "$PROJ" ;;
  idle_prompt)
    # Arrives ~60s after a turn ends with no reply. Right after a "done"
    # banner for the same session it says nothing new, and while you are
    # looking at the session it says nothing at all.
    detect_origin
    is_user_watching && exit 0
    stamped_within stopped "$SESSION" 300 && exit 0
    exec "$DIR/notify.sh" "$MSG" "$L_WAITING_TITLE" "$PROJ" "Submarine" ;;
  agent_needs_input|elicitation_dialog|elicitation_url_dialog)
    exec "$DIR/notify.sh" "$MSG" "$L_WAITING_TITLE" "$PROJ" "Submarine" ;;
  agent_completed)
    exec "$DIR/notify.sh" --done "$MSG" ;;
  auth_success|elicitation_complete|elicitation_response)
    # Housekeeping events, not calls for attention — a banner would be noise.
    exit 0 ;;
  *)
    # Informational or unknown (quota_auto_resume_*, types not invented yet):
    # a plain banner. Only a real permission request earns the approval sonar.
    exec "$DIR/notify.sh" "$MSG" ;;
esac
