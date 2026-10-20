#!/bin/bash
# PermissionRequest-hook adapter: when Claude Code is about to show a permission
# prompt and you are NOT looking at it, pops a native macOS dialog with
# Approve / Deny / Go to session / Close and returns the decision.
# Fail-safe by design: any parse error, timeout, or "go to session" exits 0
# with no output, which makes Claude Code show the normal interactive prompt.
# NOTIFY_FORCE=1 bypasses the attention gate (used for testing).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

INPUT="$(cat)"

# usage: field <jq filter> — empty when missing or unparsable.
field() {
  printf '%s' "$INPUT" | jq -r "($1) // empty" 2>/dev/null
}

SESSION="$(field '.session_id')"
CWD="$(field '.cwd')"
PROJ="${CWD##*/}"
TOOL="$(field '.tool_name')"
[ -n "$TOOL" ] || TOOL="$L_TOOL_FALLBACK"

# Where this session runs (the attention gate and the click both need it), and
# one notification group per session.
detect_origin
NOTIFY_SESSION="$SESSION"
export NOTIFY_SESSION
if [ -n "$SESSION" ]; then
  NOTIFY_GROUP="$(session_group "$SESSION")"
  export NOTIFY_GROUP
fi

# Muted means focused work: no banner, and above all no modal dialog. The
# permission falls back to Claude Code's terminal prompt, which waits quietly.
if is_muted; then
  debug_log approval "suppressed: muted"
  exit 0
fi

# Interaction tools address the user directly: an approval dialog on top of
# them is nonsense (denying your own question). But a question, or a plan ready
# for review, is exactly what you want to hear about when you are away.
case "$TOOL" in
  AskUserQuestion|ExitPlanMode)
    is_user_watching && exit 0
    if [ "$TOOL" = "AskUserQuestion" ]; then
      SUB="$L_SUB_QUESTION"
      MSG="$(field '.tool_input.questions[0].question | .[0:140]')"
      : "${MSG:=$L_ASK_FALLBACK}"
    else
      SUB="$L_SUB_PLAN"
      # The plan's first non-blank line, usually its title.
      MSG="$(field '.tool_input.plan | split("\n") | map(select(test("\\S"))) | first | sub("^[#\\s]+"; "") | .[0:140]')"
      : "${MSG:=$L_PLAN_FALLBACK}"
    fi
    if [ -n "$PROJ" ]; then TITLE="$(say "$L_YOUR_TURN_TITLE" "$PROJ")"; else TITLE="$L_YOUR_TURN_BARE"; fi
    debug_log approval "your turn: tool=$TOOL"
    stamp announced "$SESSION"
    NOTIFY_TARGET_PATH="$CWD" "$DIR/notify.sh" "$MSG" "$TITLE" "$SUB" "Submarine" >/dev/null 2>&1 || true
    exit 0 ;;
  EnterPlanMode|TodoWrite)
    exit 0 ;;
esac

# Looking at the session: its own prompt is right there. Drop any stamp left by
# an earlier request, so the Notification hook still speaks if this one waits.
if is_user_watching; then
  unstamp announced "$SESSION"
  exit 0
fi

# What the approver reads must be what runs, byte for byte: the command for
# Bash, the path for file tools, the raw input for anything else. All of it,
# never cut: the dialog scrolls, and renders control and bidi characters
# visibly instead of letting them hide or reorder text.
DETAIL="$(printf '%s' "$INPUT" \
  | jq -r '.tool_input.command // .tool_input.file_path // (.tool_input // {} | tojson)' 2>/dev/null || true)"
case "$DETAIL" in null|'{}') DETAIL="" ;; esac
# Claude's own one-line summary of the command, when the tool has one.
DESC="$(field '.tool_input.description')"

# With several sessions running, "Claude wants to use Bash" alone is a guess.
if [ -n "$PROJ" ]; then
  HEADLINE="$(say "$L_APPROVAL_HEADLINE" "$TOOL" "$PROJ")"
  BRANCH="$(git -C "$CWD" branch --show-current 2>/dev/null || true)"
  [ -n "$BRANCH" ] && HEADLINE="$HEADLINE ($BRANCH)"
else
  HEADLINE="$(say "$L_APPROVAL_PROMPT" "$TOOL")"
fi

debug_log approval "tool=$TOOL detail=${DETAIL:0:80}"

# Banner + sound so the dialog is never missed even off-screen. macOS shows
# notification previews on the LOCK SCREEN by default, so the command — which
# can carry a token or a password — is only in the banner when the user asks
# for it. Claude's description of it is safe to show. The dialog always shows
# the command, and that needs an unlocked session.
if [ "${NOTIFY_BANNER_DETAIL:-tool}" = "full" ]; then
  BANNER="$TOOL: ${DETAIL:-$L_NO_DETAILS}"
elif [ -n "$DESC" ]; then
  BANNER="$DESC"
else
  BANNER="$(say "$L_APPROVAL_PROMPT" "$TOOL")"
fi
# Title: which project. Subtitle: which tool. Body: what it is for.
if [ -n "$PROJ" ]; then BTITLE="$(say "$L_TITLE_APPROVAL_IN" "$PROJ")"; else BTITLE=""; fi
stamp announced "$SESSION"
NOTIFY_TARGET_PATH="$CWD" "$DIR/notify.sh" --approval "$BANNER" "$BTITLE" "$TOOL" >/dev/null 2>&1 || true

# "Always approve": the rule Claude Code itself offers as "don't ask again"
# (permission_suggestions), returned verbatim, never one built here. Shown
# only when there is one to offer.
ALWAYS_RULE="$(printf '%s' "$INPUT" | jq -c '[.permission_suggestions[]?
  | select(.type == "addRules" and .behavior == "allow")] | first // empty' 2>/dev/null)"
BUTTONS="$L_APPROVAL_BUTTONS"
if [ -n "$ALWAYS_RULE" ]; then
  RULE_TEXT="$(printf '%s' "$ALWAYS_RULE" | jq -r '[.rules[]? | .toolName + (if .ruleContent then "(" + .ruleContent + ")" else "" end)]
    | join(", ") | .[0:48] | gsub("[|]"; "/")' 2>/dev/null)"
  [ -n "$RULE_TEXT" ] && BUTTONS="${BUTTONS%%|*}|$(say "$L_APPROVE_ALWAYS" "$RULE_TEXT")::always|${BUTTONS#*|}"
fi

# Parallel sessions wait their turn; giving up leaves the banner and Claude
# Code's own prompt, which waits in the terminal.
if ! dialog_lock; then
  debug_log approval "no dialog: queue timed out or user came back"
  exit 0
fi
RES="$(run_dialog "$HEADLINE" "$DESC" "$DIR/claude-logo.png" \
  "$BUTTONS" "${NOTIFY_DIALOG_TIMEOUT:-50}" "$DETAIL" until-watching)"
dialog_unlock

debug_log approval "decision=${RES:-<none>}"

case "$RES" in
  approve)
    printf '%s' "$INPUT" | jq -c '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedInput:(.tool_input // {})}}}'
    ;;
  always)
    printf '%s' "$INPUT" | jq -c --argjson rule "$ALWAYS_RULE" \
      '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedInput:(.tool_input // {}),updatedPermissions:[$rule]}}}'
    ;;
  deny)
    # jq builds it so the reason survives quotes or anything else in the name.
    jq -cn --arg reason "$(say "$L_DENY_MESSAGE" "${USER:-$L_USER_FALLBACK}")" \
      '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"deny",message:$reason}}}'
    ;;
  editor)
    # Land where the request came from: the exact terminal tab when the host
    # exposes one, otherwise the window holding this project.
    focus_now "$CWD" >/dev/null 2>&1 || true
    exit 0 ;;
  *)
    # Close/Esc, timeout, or any failure: no decision, normal prompt.
    exit 0 ;;
esac
