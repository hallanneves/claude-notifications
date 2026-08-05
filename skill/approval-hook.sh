#!/bin/bash
# PermissionRequest-hook adapter: when Claude Code is about to show a permission
# prompt and you are AWAY from the editor/terminal, pops a native macOS dialog
# with Aprovar / Abrir no editor / Negar buttons and returns the decision.
# Fail-safe by design: any parse error, timeout, or "Abrir no editor" exits 0
# with no output, which makes Claude Code show the normal interactive prompt.
# NOTIFY_FORCE=1 bypasses the frontmost-app gate (used for testing).
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

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // "ferramenta"' 2>/dev/null)"

# Interaction tools address the user directly — an approval dialog on top of
# them is nonsense (denying your own question). Let the normal UI handle them.
case "$TOOL" in
  AskUserQuestion|EnterPlanMode|ExitPlanMode|TodoWrite)
    exit 0 ;;
esac
DETAIL="$(printf '%s' "$INPUT" \
  | jq -r '.tool_input.command // .tool_input.file_path // (.tool_input | tostring) // ""' 2>/dev/null \
  | head -c 220 | tr '\n' ' ' | tr '"' "'" | tr '\\' '/')"

PROMPT="Claude quer usar: $TOOL"
[ -n "$DETAIL" ] && PROMPT="$PROMPT — $DETAIL"

# Banner + sound so the dialog is never missed even off-screen
"$HOME/.claude/skills/notify/notify.sh" --approval "$TOOL: ${DETAIL:-sem detalhes}" >/dev/null 2>&1 || true

# 'activate' first: a dialog from a background process opens BEHIND the
# frontmost app (or on another Space) unless osascript activates itself.
RES="$(osascript -e "activate" -e "display dialog \"$PROMPT\" with title \"Claude Code — aprovação\" buttons {\"Negar\", \"Abrir no editor\", \"Aprovar\"} default button \"Abrir no editor\" giving up after 50 with icon caution" 2>/dev/null)" || RES=""

case "$RES" in
  *"gave up:true"*)
    exit 0 ;;
  *"button returned:Aprovar"*)
    printf '%s' "$INPUT" | jq -c '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedInput:(.tool_input // {})}}}'
    ;;
  *"button returned:Negar"*)
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Negado pelo Hallan via dialog de notificação"}}}'
    ;;
  *"button returned:Abrir no editor"*)
    open -b com.microsoft.VSCode 2>/dev/null || true
    exit 0 ;;
  *)
    exit 0 ;;
esac
