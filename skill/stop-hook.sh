#!/bin/bash
# Stop-hook adapter: "work done" banner when Claude finishes a turn.
# Suppressed while the editor/terminal is the frontmost app (you can already see
# the result there); fails open — if the frontmost check errors, it notifies.
# Set NOTIFY_FORCE=1 to bypass the suppression (used for testing).
set -uo pipefail

INPUT="$(cat)"

if [ "${NOTIFY_FORCE:-0}" != "1" ]; then
  FRONT="$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
    | sed -E 's/.*"(LSDisplayName|name)"="([^"]+)".*/\2/')"
  case "$FRONT" in
    Code|"Visual Studio Code"|"Code - Insiders"|Electron|Terminal|iTerm2|kitty|Ghostty|WezTerm|Alacritty)
      exit 0 ;;
  esac
fi

PROJ="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
PROJ="${PROJ##*/}"
exec "$HOME/.claude/skills/notify/notify.sh" --done "Terminei${PROJ:+ em $PROJ} — pode conferir" "" "${PROJ:+projeto $PROJ}"
