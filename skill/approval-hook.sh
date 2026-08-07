#!/bin/bash
# PermissionRequest-hook adapter: when Claude Code is about to show a permission
# prompt and you are AWAY from the editor/terminal, pops a native macOS dialog
# with Approve / Open in editor / Deny buttons and returns the decision.
# Fail-safe by design: any parse error, timeout, or "open in editor" exits 0
# with no output, which makes Claude Code show the normal interactive prompt.
# NOTIFY_FORCE=1 bypasses the frontmost-app gate (used for testing).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

INPUT="$(cat)"

front_is_editor && exit 0

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
[ -n "$TOOL" ] || TOOL="$L_TOOL_FALLBACK"

# Interaction tools address the user directly — an approval dialog on top of
# them is nonsense (denying your own question). Let the normal UI handle them.
case "$TOOL" in
  AskUserQuestion|EnterPlanMode|ExitPlanMode|TodoWrite)
    exit 0 ;;
esac

RAW="$(printf '%s' "$INPUT" \
  | jq -r '.tool_input.command // .tool_input.file_path // (.tool_input // {} | tostring)' 2>/dev/null || true)"
case "$RAW" in null|'{}') RAW="" ;; esac
# shellcheck disable=SC1003  # tr '\\' é um escape de tr, não de aspas
DETAIL="$(printf '%s' "$RAW" | head -c 350 | tr '\n' ' ' | tr '"' "'" | tr '\\' '/')"
# Never hide the tail of a long command silently from the approver.
[ "${#RAW}" -gt 350 ] && DETAIL="$DETAIL $L_TRUNCATED"

PROMPT="$(say "$L_APPROVAL_PROMPT" "$TOOL")"
[ -n "$DETAIL" ] && PROMPT="$PROMPT — $DETAIL"

# Banner + sound so the dialog is never missed even off-screen
"$DIR/notify.sh" --approval "$TOOL: ${DETAIL:-$L_NO_DETAILS}" >/dev/null 2>&1 || true

RES="$(run_dialog "$L_APPROVAL_TITLE" "$PROMPT" "$DIR/claude-logo.png" \
  "$L_APPROVAL_BUTTONS" "${NOTIFY_DIALOG_TIMEOUT:-50}")"

case "$RES" in
  approve)
    printf '%s' "$INPUT" | jq -c '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedInput:(.tool_input // {})}}}'
    ;;
  deny)
    # jq builds it so the reason survives quotes or anything else in the name.
    jq -cn --arg reason "$(say "$L_DENY_MESSAGE" "${USER:-$L_USER_FALLBACK}")" \
      '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"deny",message:$reason}}}'
    ;;
  editor)
    open -b "${NOTIFY_ACTIVATE:-$NOTIFY_ACTIVATE_DEFAULT}" 2>/dev/null || true
    exit 0 ;;
  *)
    # "Fechar"/Esc, timeout, or any failure: no decision, normal prompt.
    exit 0 ;;
esac
