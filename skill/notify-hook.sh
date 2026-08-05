#!/bin/bash
# Notification-hook adapter: reads Claude Code's hook JSON from stdin and fires
# a native macOS banner via notify.sh. Wired in ~/.claude/settings.json (hooks.Notification).
set -uo pipefail

MSG="$(jq -r '.message // empty' 2>/dev/null)"
[ -z "$MSG" ] && MSG="Claude Code precisa de você"

case "$MSG" in
  *permission*|*permissão*|*approval*)
    exec "$HOME/.claude/skills/notify/notify.sh" --approval "$MSG" ;;
  *waiting*|*input*|*esperando*)
    exec "$HOME/.claude/skills/notify/notify.sh" "$MSG" "💬 Claude está esperando você" "" "Submarine" ;;
  *)
    exec "$HOME/.claude/skills/notify/notify.sh" --approval "$MSG" "🔔 Claude Code" ;;
esac
