#!/bin/bash
# PermissionRequest-hook adapter: when Claude Code is about to show a permission
# prompt and you are AWAY from the editor/terminal, pops a native macOS dialog
# with Aprovar / Abrir no editor / Negar buttons and returns the decision.
# Fail-safe by design: any parse error, timeout, or "Abrir no editor" exits 0
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
[ -n "$TOOL" ] || TOOL="ferramenta"

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
[ "${#RAW}" -gt 350 ] && DETAIL="$DETAIL [TRUNCADO — use Abrir no editor para ver o comando completo]"

PROMPT="Claude quer usar: $TOOL"
[ -n "$DETAIL" ] && PROMPT="$PROMPT — $DETAIL"

# Banner + sound so the dialog is never missed even off-screen
"$DIR/notify.sh" --approval "$TOOL: ${DETAIL:-sem detalhes}" >/dev/null 2>&1 || true

# The dialog owns no clock of its own (an NSTimer never fires inside a modal
# run loop), so the timeout lives here: run it detached and kill it if nobody
# answers. A killed dialog prints nothing, which is the fail-safe path.
OUT="$(mktemp)"
TIMED_OUT="$OUT.timeout"
trap 'rm -f "$OUT" "$TIMED_OUT"' EXIT
osascript -l JavaScript "$DIR/approval-dialog.js" "$PROMPT" "$DIR/claude-logo.png" >"$OUT" 2>/dev/null &
DIALOG_PID=$!
# The watchdog MUST NOT inherit our stdout: a command substitution upstream
# stays blocked until every writer closes the pipe, which would hold the
# decision hostage for the full timeout after the user already answered.
( sleep "${NOTIFY_DIALOG_TIMEOUT:-50}"; : > "$TIMED_OUT"; kill "$DIALOG_PID" 2>/dev/null ) >/dev/null 2>&1 &
WATCHDOG=$!
wait "$DIALOG_PID" 2>/dev/null
{ kill "$WATCHDOG" 2>/dev/null; wait "$WATCHDOG" 2>/dev/null; } 2>/dev/null

# A dialog torn down mid-flight can still flush a token (AppKit unwinds the
# modal session as the process dies, and that has produced a bogus "approve").
# Whatever the corpse wrote, a timeout is never a decision.
if [ -f "$TIMED_OUT" ]; then
  RES=""
else
  RES="$(cat "$OUT")"
fi

case "$RES" in
  approve)
    printf '%s' "$INPUT" | jq -c '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedInput:(.tool_input // {})}}}'
    ;;
  deny)
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Negado por %s via dialog de notificação"}}}' "${USER:-usuário}"
    ;;
  editor)
    open -b "${NOTIFY_ACTIVATE:-$NOTIFY_ACTIVATE_DEFAULT}" 2>/dev/null || true
    exit 0 ;;
  *)
    # "Fechar"/Esc, timeout, or any failure: no decision, normal prompt.
    exit 0 ;;
esac
