#!/bin/bash
# Notification-hook adapter: reads Claude Code's hook JSON from stdin and fires
# a native macOS banner via notify.sh. Wired in ~/.claude/settings.json (hooks.Notification).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

INPUT="$(cat)"
TYPE="$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)"
MSG="$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)"
[ -z "$MSG" ] && MSG="Claude Code precisa de você"

# notification_type is the machine-readable field; the message keywords are a
# fallback for Claude Code versions that predate it.
if [ -z "$TYPE" ]; then
  case "$MSG" in
    *permission*|*permissão*|*approval*) TYPE="permission_prompt" ;;
    *waiting*|*input*|*esperando*)       TYPE="idle_prompt" ;;
  esac
fi

case "$TYPE" in
  permission_prompt)
    exec "$DIR/notify.sh" --approval "$MSG" ;;
  idle_prompt|agent_needs_input|elicitation_dialog)
    exec "$DIR/notify.sh" "$MSG" "Claude está esperando você" "" "Submarine" ;;
  agent_completed)
    exec "$DIR/notify.sh" --done "$MSG" ;;
  auth_success|elicitation_complete|elicitation_response)
    # Housekeeping events, not calls for attention — a banner would be noise.
    exit 0 ;;
  *)
    exec "$DIR/notify.sh" --approval "$MSG" "Claude Code" ;;
esac
