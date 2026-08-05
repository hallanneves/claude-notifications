#!/bin/bash
# Stop-hook adapter: "work done" banner when Claude finishes a turn.
# Suppressed while an editor/terminal is the frontmost app (you can already see
# the result there); fails open — if the frontmost check errors, it notifies.
# Set NOTIFY_FORCE=1 to bypass the suppression (used for testing).
set -uo pipefail

CONF="$HOME/.claude/skills/notify/notify.conf"
[ -f "$CONF" ] && . "$CONF"

INPUT="$(cat)"

if [ "${NOTIFY_FORCE:-0}" != "1" ]; then
  FRONT="$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
    | sed -E 's/.*"(LSDisplayName|name)"="([^"]+)".*/\2/')"
  case "$FRONT" in
    Code|"Visual Studio Code"|"Code - Insiders"|Cursor|Windsurf|Zed|Electron|Terminal|iTerm2|kitty|Ghostty|WezTerm|Alacritty|Warp|Hyper|Tabby)
      exit 0 ;;
  esac
  if [ -n "$FRONT" ] && [ -n "${NOTIFY_FRONT_APPS:-}" ]; then
    case ",$NOTIFY_FRONT_APPS," in
      *",$FRONT,"*) exit 0 ;;
    esac
  fi
fi

PROJ="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
PROJ="${PROJ##*/}"
exec "$HOME/.claude/skills/notify/notify.sh" --done "Terminei${PROJ:+ em $PROJ} — pode conferir" "" "${PROJ:+projeto $PROJ}"
