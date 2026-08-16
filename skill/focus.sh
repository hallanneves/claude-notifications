#!/bin/bash
# focus.sh — bring back the exact place the notification came from.
#
# usage: focus.sh <cwd> <term_program> <iterm_session_id> <tty>
#
# The arguments are captured while the HOOK runs and baked into the click
# action, because by the time someone clicks, none of it is reachable any more.
#
# What is actually possible, per host:
#   - iTerm2 / Terminal.app: the exact tab, matched by session id or tty.
#   - An editor (VSCode, Cursor, Zed…): the WINDOW holding that folder. Neither
#     exposes its windows or tabs to AppleScript, so the folder is the ceiling;
#     `open -b <bundle> <folder>` is what focuses the right window.
# Anything unknown falls back to activating the configured app.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

CWD="${1:-}"
TERM_PROG="${2:-}"
ITERM_ID="${3:-}"
TTY_PATH="${4:-}"

focus_iterm() {
  # iTerm2 hands out "w0t1p0:UUID"; the session id is the part after the colon.
  local uuid="${1##*:}"
  [ -n "$uuid" ] || return 1
  osascript >/dev/null 2>&1 <<EOF
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if id of s is "$uuid" then
          select w
          select t
          select s
          activate
          return
        end if
      end repeat
    end repeat
  end repeat
  error "session not found"
end tell
EOF
}

focus_terminal_app() {
  local tty="$1"
  [ -n "$tty" ] || return 1
  osascript >/dev/null 2>&1 <<EOF
tell application "Terminal"
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t is "$tty" then
        set selected tab of w to t
        set index of w to 1
        activate
        return
      end if
    end repeat
  end repeat
  error "tab not found"
end tell
EOF
}

# Most specific first; each falls through when the session is gone.
if [ -n "$ITERM_ID" ] && focus_iterm "$ITERM_ID"; then
  exit 0
fi

if [ "$TERM_PROG" = "Apple_Terminal" ] && focus_terminal_app "$TTY_PATH"; then
  exit 0
fi

eval "$(open_target_cmd "$CWD")" 2>/dev/null || true
