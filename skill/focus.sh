#!/bin/bash
# focus.sh — bring back the exact place the notification came from.
#
# usage: focus.sh <cwd> <term_program> <iterm_session_id> <tty> [host_bundle]
#
# The arguments are captured while the HOOK runs and baked into the click
# action, because by the time someone clicks, none of it is reachable any more.
#
# Most specific first, and never an app other than the one hosting the session:
#   - iTerm2 / Terminal.app: the exact tab, matched by session id or tty.
#   - An editor (VSCode, Cursor, Zed…): the WINDOW holding the project, by its
#     workspace root (see editor_root in notify-lib.sh).
#   - Anything else, or a tab that is gone: the host app itself.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

CWD="${1:-}"
TERM_PROG="${2:-}"
ITERM_ID="${3:-}"
TTY_PATH="${4:-}"
HOST="${5:-}"
# Banners posted before the host travelled with the click: the terminal still
# names itself. Never guess from this process's own environment, which is the
# notifier's.
if [ -z "$HOST" ]; then
  case "$TERM_PROG" in
    Apple_Terminal) HOST="com.apple.Terminal" ;;
    iTerm.app)      HOST="com.googlecode.iterm2" ;;
  esac
  HOST="${NOTIFY_ACTIVATE:-$HOST}"
fi

# Runs the AppleScript on stdin with the given arguments, so values are never
# spliced into the script's text. 0: done. 2: macOS refused the Automation
# permission (-1743, -1744). 1: anything else (the tab closed, the app quit).
osa() {
  local err
  err="$(osascript - "$@" 2>&1 >/dev/null)" && return 0
  case "$err" in *-1743*|*-1744*) return 2 ;; esac
  return 1
}

focus_iterm() {
  # iTerm2 hands out "w0t1p0:UUID"; the session id is the part after the colon.
  local uuid="${1##*:}"
  [ -n "$uuid" ] || return 1
  osa "$uuid" <<'EOF'
on run argv
  set wanted to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is wanted then
            select w
            select t
            select s
            activate
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
  error "session not found"
end run
EOF
}

focus_terminal_app() {
  local tty="$1"
  [ -n "$tty" ] || return 1
  osa "$tty" <<'EOF'
on run argv
  set wanted to item 1 of argv
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is wanted then
          set selected tab of w to t
          set index of w to 1
          activate
          return
        end if
      end repeat
    end repeat
  end tell
  error "tab not found"
end run
EOF
}

# A refused Automation permission used to be invisible: the click just landed
# one level up, every time, with no hint why. Say so once per app, with a click
# that opens the right pane of System Settings. A later success re-arms it.
tcc_hint() {
  local app="$1" mark="$NOTIFY_STATE_DIR/.tcc-hint-$1"
  [ -f "$mark" ] && return 0
  mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null
  : > "$mark" 2>/dev/null
  debug_log focus "automation refused for $app"
  NOTIFY_EXECUTE="open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Automation'" \
    "$DIR/notify.sh" --info "$(say "$L_TCC_HINT" "$app")" "$L_TCC_TITLE" >/dev/null 2>&1 || true
}

# usage: try_tab <app name> <focus function> <args...>
try_tab() {
  local app="$1" rc
  shift
  "$@"
  rc=$?
  case "$rc" in
    0) rm -f "$NOTIFY_STATE_DIR/.tcc-hint-$app" 2>/dev/null; return 0 ;;
    2) tcc_hint "$app" ;;
  esac
  return 1
}

# One level up, and never another app: the window holding the project when the
# host is an editor, otherwise the host app itself.
activate_host() {
  local root mode="${NOTIFY_ACTIVATE_PATH:-auto}"
  [ -n "$HOST" ] || return 0
  if [ "$mode" != never ] && is_editor_bundle "$HOST" && root="$(editor_root "$CWD")"; then
    open -b "$HOST" "$root"
  elif [ "$mode" = always ] && [ -n "$CWD" ]; then
    open -b "$HOST" "$CWD"
  else
    open -b "$HOST"
  fi
}

if [ -n "$ITERM_ID" ] && try_tab iTerm2 focus_iterm "$ITERM_ID"; then
  exit 0
fi

if [ "$TERM_PROG" = "Apple_Terminal" ] && try_tab Terminal focus_terminal_app "$TTY_PATH"; then
  exit 0
fi

activate_host 2>/dev/null || true
