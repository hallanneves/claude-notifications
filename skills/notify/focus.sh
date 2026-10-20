#!/bin/bash
# focus.sh — bring back the exact place the notification came from.
#
# usage: focus.sh --cwd DIR --kind KIND --host BUNDLE [--term-program NAME]
#                 [--iterm SESSION_ID] [--tty TTY] [--herdr-bin PATH]
#                 [--herdr-socket PATH] [--herdr-pane ID] [--session ID]
#                 [--pids "PID PID ..."] [--report FILE]
#        focus.sh <cwd> <term_program> <iterm_session_id> <tty> [host_bundle]
#                 (the form clicks posted before 1.8 still carry)
#
# The arguments are captured while the HOOK runs and baked into the click
# action, because by the time someone clicks, none of it is reachable any more.
#
# Most specific first, and never an app other than the one hosting the session:
#   - herdr: the session's pane, found by its Claude session id, then the
#     terminal tab running the herdr client.
#   - An editor with the bridge extension (vscode-bridge/): the window owning
#     the session, found by process ancestry (--pids), and in it the Claude
#     tab (--session) or the integrated terminal running Claude.
#   - iTerm2 / Terminal.app: the exact tab, matched by session id or tty.
#   - An editor (VSCode, Cursor, Zed…): the WINDOW holding the project, by its
#     workspace root (see editor_root in notify-lib.sh).
#   - Anything else, or a tab that is gone: the host app itself.
# --report appends one line per step that worked, for doctor.sh --test.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

CWD="" KIND="" HOST="" TERM_PROG="" ITERM_ID="" TTY_PATH=""
HERDR_BIN="" HERDR_SOCK="" HERDR_PANE="" SESSION="" REPORT="" PIDS=""

if [ "${1:-}" = "${1#--}" ]; then
  CWD="${1:-}" TERM_PROG="${2:-}" ITERM_ID="${3:-}" TTY_PATH="${4:-}" HOST="${5:-}"
else
  while [ $# -ge 2 ]; do
    case "$1" in
      --cwd)          CWD="$2" ;;
      --kind)         KIND="$2" ;;
      --host)         HOST="$2" ;;
      --term-program) TERM_PROG="$2" ;;
      --iterm)        ITERM_ID="$2" ;;
      --tty)          TTY_PATH="$2" ;;
      --herdr-bin)    HERDR_BIN="$2" ;;
      --herdr-socket) HERDR_SOCK="$2" ;;
      --herdr-pane)   HERDR_PANE="$2" ;;
      --session)      SESSION="$2" ;;
      --pids)         PIDS="$2" ;;
      --report)       REPORT="$2" ;;
    esac
    shift 2
  done
fi

# Clicks posted before the host travelled with them: the terminal still names
# itself. Never guess from this process's own environment, which is the
# notifier's.
if [ -z "$HOST" ]; then
  case "$TERM_PROG" in
    Apple_Terminal) HOST="com.apple.Terminal" ;;
    iTerm.app)      HOST="com.googlecode.iterm2" ;;
  esac
  HOST="${NOTIFY_ACTIVATE:-$HOST}"
fi

report() {
  [ -n "$REPORT" ] && printf '%s\n' "$*" >> "$REPORT"
  return 0
}

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

focus_iterm_tty() {
  local tty="$1"
  [ -n "$tty" ] || return 1
  osa "$tty" <<'EOF'
on run argv
  set wanted to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if tty of s is wanted then
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

# The terminal tab of a given app holding <tty>.
# usage: focus_tab_in <bundle id> <tty>
focus_tab_in() {
  case "$1" in
    com.apple.Terminal)    try_tab Terminal focus_terminal_app "$2" ;;
    com.googlecode.iterm2) try_tab iTerm2 focus_iterm_tty "$2" ;;
    *) return 1 ;;
  esac
}

herdr_cli() {
  if [ -n "$HERDR_SOCK" ]; then
    HERDR_SOCKET_PATH="$HERDR_SOCK" "$HERDR_BIN" "$@" 2>/dev/null
  else
    "$HERDR_BIN" "$@" 2>/dev/null
  fi
}

# The session's pane inside herdr. Pane ids change when a pane moves; the
# Claude session id does not, so it is looked up first.
focus_herdr_pane() {
  local pane="$HERDR_PANE" listed
  [ -n "$HERDR_BIN" ] && [ -x "$HERDR_BIN" ] || return 1
  if [ -n "$SESSION" ]; then
    listed="$(herdr_cli agent list | jq -r --arg s "$SESSION" \
      '[.result.agents[]? | select(.agent_session.value == $s) | .pane_id] | first // empty' 2>/dev/null)"
    [ -n "$listed" ] && pane="$listed"
  fi
  [ -n "$pane" ] || return 1
  herdr_cli agent focus "$pane" >/dev/null || return 1
  report "herdr-pane $pane"
}

# The terminal tab running a herdr client (see herdr_clients). With several
# clients attached, the first one that can be focused wins.
raise_herdr_client() {
  local tty bundle
  while read -r tty bundle; do
    [ -n "$bundle" ] || continue
    if focus_tab_in "$bundle" "$tty"; then
      report "terminal-tab $bundle $tty"
      return 0
    fi
    open -b "$bundle" 2>/dev/null
    report "app $bundle"
    return 0
  done <<< "$(herdr_clients)"
  return 1
}

# The exact Claude tab or integrated terminal, asked of the one window that
# owns the session (bridge_window) over its own socket. That window is raised
# first by its own workspace, which `open` focuses rather than duplicates.
focus_editor_session() {
  local owner socket open_path request reply
  [ -n "$PIDS" ] && [ -n "$HOST" ] || return 1
  owner="$(bridge_window "$PIDS")" || return 1
  socket="$(printf '%s' "$owner" | jq -r '.socket // empty')"
  open_path="$(printf '%s' "$owner" | jq -r '.openPath // empty')"
  [ -n "$socket" ] || return 1
  if [ "$KIND" = "editor-terminal" ]; then
    request="$(jq -cn --arg pids "$PIDS" \
      '{cmd: "show-terminal", pids: ($pids | split(" ") | map(select(length > 0) | tonumber))}')"
  else
    [ -n "$SESSION" ] || return 1
    request="$(jq -cn --arg s "$SESSION" '{cmd: "reveal-session", session: $s}')"
  fi
  if [ -n "$open_path" ]; then
    open -b "$HOST" "$open_path" 2>/dev/null
  else
    open -b "$HOST" 2>/dev/null
  fi
  reply="$(printf '%s\n' "$request" | nc -U -w 2 "$socket" 2>/dev/null)"
  printf '%s' "$reply" | jq -e '.ok == true' >/dev/null 2>&1 || return 1
  report "editor-$(printf '%s' "$reply" | jq -r '.did') $open_path"
}

# One level up, and never another app: the window holding the project when the
# host is an editor, otherwise the host app itself.
activate_host() {
  local root mode="${NOTIFY_ACTIVATE_PATH:-auto}"
  [ -n "$HOST" ] || return 0
  if [ "$mode" != never ] && is_editor_bundle "$HOST" && root="$(editor_root "$CWD")"; then
    open -b "$HOST" "$root"
    report "editor-window $HOST $root"
  elif [ "$mode" = always ] && [ -n "$CWD" ]; then
    open -b "$HOST" "$CWD"
    report "app $HOST $CWD"
  else
    open -b "$HOST"
    report "app $HOST"
  fi
}

if [ "$KIND" = "herdr" ]; then
  # The pane first (no permission needed), then the tab showing it.
  focus_herdr_pane
  raise_herdr_client && exit 0
  activate_host 2>/dev/null || true
  exit 0
fi

case "$KIND" in
  editor-extension|editor-terminal)
    focus_editor_session && exit 0
    activate_host 2>/dev/null || true
    exit 0 ;;
esac

if [ -n "$ITERM_ID" ] && try_tab iTerm2 focus_iterm "$ITERM_ID"; then
  report "iterm-session $ITERM_ID"
  exit 0
fi

if [ "$TERM_PROG" = "Apple_Terminal" ] && try_tab Terminal focus_terminal_app "$TTY_PATH"; then
  report "terminal-tab com.apple.Terminal $TTY_PATH"
  exit 0
fi

activate_host 2>/dev/null || true
