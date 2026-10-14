#!/bin/bash
# notify-lib.sh — shared constants and helpers for the notify skill scripts
# (notify.sh, stop-hook.sh, approval-hook.sh) and for the installer scripts at
# the repo root. Meant to be sourced, not executed.
# shellcheck disable=SC2034  # constants are consumed by the sourcing scripts

DEDICATED_APP_NAME="Claude Code Notifier"
DEDICATED_APP="$HOME/Applications/$DEDICATED_APP_NAME.app"
DEDICATED_BUNDLE_ID="com.github.hallanneves.claude-notifier"

# Where check-update.sh looks for newer tags and update.sh clones from when the
# original working copy is gone. Override with NOTIFY_UPDATE_REPO to track a
# fork. load_notify_conf may reset this, so it is only a default.
NOTIFY_UPDATE_REPO_DEFAULT="https://github.com/hallanneves/claude-notifications.git"

# Optional user config, shared by every script that sources this lib.
load_notify_conf() {
  # shellcheck disable=SC1090,SC1091
  [ -f "$HOME/.claude/skills/notify/notify.conf" ] && . "$HOME/.claude/skills/notify/notify.conf"
  : "${NOTIFY_UPDATE_REPO:=$NOTIFY_UPDATE_REPO_DEFAULT}"
  # After the conf, so NOTIFY_LANG set there wins over the system locale.
  load_lang
  return 0
}

# Resolves the interface language and sources its catalogue, defining every
# L_* string. NOTIFY_LANG (conf or environment) wins; otherwise the macOS
# locale decides, and anything without a catalogue falls back to English.
load_lang() {
  local dir want
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  want="${NOTIFY_LANG:-}"
  if [ -z "$want" ]; then
    # AppleLocale is the language the user actually reads; $LANG is often
    # just C.UTF-8 under a hook and would say nothing.
    want="$(defaults read -g AppleLocale 2>/dev/null)"
    [ -z "$want" ] && want="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  fi
  # "pt_BR" -> pt, "en_BR" -> en (region is irrelevant: en_BR reads English).
  want="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')"
  want="${want%%[_.-]*}"

  [ -f "$dir/lang/$want.sh" ] || want="en"
  # shellcheck disable=SC1090
  . "$dir/lang/$want.sh"
  NOTIFY_LANG_RESOLVED="$want"
}

# Runtime state: the mute stamp, the per-session "already announced" stamps,
# the Automation hint stamps. NOTIFY_STATE_DIR moves all of it.
NOTIFY_STATE_DIR="${NOTIFY_STATE_DIR:-$HOME/.claude/skills/notify}"
MUTE_FILE="${MUTE_FILE:-$NOTIFY_STATE_DIR/.mute-until}"

# The app hosting this session: what a click falls back to, so it never lands
# in an app the session has nothing to do with (it used to be VSCode for
# everyone, which launched VSCode for a click on a Terminal session).
# NOTIFY_ACTIVATE (notify.conf or environment) overrides. Otherwise the
# terminal names itself, and macOS stamps every process an app launches with
# that app's bundle id. Prints nothing when there is no clue at all.
host_bundle() {
  if [ -n "${NOTIFY_ACTIVATE:-}" ]; then
    printf '%s' "$NOTIFY_ACTIVATE"
    return 0
  fi
  case "${TERM_PROGRAM:-}" in
    Apple_Terminal) printf 'com.apple.Terminal'; return 0 ;;
    iTerm.app)      printf 'com.googlecode.iterm2'; return 0 ;;
  esac
  printf '%s' "${__CFBundleIdentifier:-}"
}

# iTerm2's session id, but only when iTerm2 itself runs this session. Inside
# tmux or herdr it is inherited from whichever shell started the server, and
# names a tab that has nothing to do with this session.
iterm_session() {
  if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
    printf '%s' "${ITERM_SESSION_ID:-}"
  fi
  return 0
}

# Single-quotes a value for embedding in a shell command string.
shq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# The controlling terminal of this session, as a device path — empty when there
# is none, which is the case whenever Claude Code runs as an editor extension.
# NOTIFY_TTY overrides the lookup for tests.
current_tty() {
  local tty
  tty="${NOTIFY_TTY-$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')}"
  case "$tty" in
    ''|'??'|'?') printf '' ;;
    /dev/*)      printf '%s' "$tty" ;;
    *)           printf '/dev/%s' "$tty" ;;
  esac
}

# The click action, built while the hook still has the context: which terminal
# session raised this, which project it was in, and which app hosts it.
focus_cmd() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s %s %s %s %s %s' \
    "$(shq "$dir/focus.sh")" "$(shq "$1")" "$(shq "${TERM_PROGRAM:-}")" \
    "$(shq "$(iterm_session)")" "$(shq "$(current_tty)")" "$(shq "$(host_bundle)")"
}

# Same thing, run right now instead of baked into a click.
focus_now() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "$dir/focus.sh" "$1" "${TERM_PROGRAM:-}" "$(iterm_session)" "$(current_tty)" "$(host_bundle)"
}

# True when a click has somewhere specific to land: a terminal session we can
# name, or a project an editor can focus.
has_focus_target() {
  [ -n "$(iterm_session)" ] && return 0
  [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ] && return 0
  should_open_path "$1"
}

# Only editors get a folder: handing a path to a terminal bundle opens a NEW
# window instead of focusing anything. NOTIFY_ACTIVATE_PATH=always|never
# overrides the guess.
should_open_path() {
  local path="$1" mode="${NOTIFY_ACTIVATE_PATH:-auto}"
  [ -n "$path" ] || return 1
  case "$mode" in
    never)  return 1 ;;
    always) return 0 ;;
  esac
  is_editor_bundle "$(host_bundle)"
}

# The workspace folder of the editor window that holds <cwd>, read from the
# lock files the Claude Code extension keeps for each running editor
# (~/.claude/ide/*.lock). `open -b <editor> <folder>` focuses a window only
# when <folder> is exactly what that window has open: a subfolder or a
# worktree opens a NEW window. So the deepest workspace containing cwd is the
# only safe thing to hand over. Fails when no live editor has it.
editor_root() {
  local cwd="$1" best="" lock pid dir
  [ -n "$cwd" ] || return 1
  for lock in "$HOME"/.claude/ide/*.lock; do
    [ -f "$lock" ] || continue
    pid="$(jq -r '.pid // empty' "$lock" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || continue
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      case "${cwd%/}/" in
        "${dir%/}/"*) [ "${#dir}" -gt "${#best}" ] && best="$dir" ;;
      esac
    done < <(jq -r '.workspaceFolders[]? // empty' "$lock" 2>/dev/null)
  done
  [ -n "$best" ] || return 1
  printf '%s' "$best"
}

is_editor_bundle() {
  case "$1" in
    com.microsoft.VSCode*|com.visualstudio.code*|com.todesktop.*|com.exafunction.*\
      |dev.zed.*|com.sublimetext.*|com.jetbrains.*|com.apple.dt.Xcode)
      return 0 ;;
  esac
  return 1
}

# Prints the mute deadline ("forever", or an epoch), or nothing when not muted.
# An expired stamp is cleared here so nothing else has to think about it.
mute_until() {
  local raw
  [ -f "$MUTE_FILE" ] || return 0
  raw="$(cat "$MUTE_FILE" 2>/dev/null)"
  case "$raw" in
    forever) printf 'forever'; return 0 ;;
    ''|*[!0-9]*) rm -f "$MUTE_FILE"; return 0 ;;
  esac
  if [ "$(date +%s)" -ge "$raw" ]; then
    rm -f "$MUTE_FILE"
    return 0
  fi
  printf '%s' "$raw"
}

# True while notifications are silenced. Callers must stay silent AND skip any
# dialog: a modal window is the loudest interruption of all.
is_muted() {
  [ -n "$(mute_until)" ]
}

# Keeps an append-only log from growing forever: past the cap, only the tail
# is worth reading anyway.
rotate_log() {
  local file="$1" max="${2:-65536}" size
  [ -f "$file" ] || return 0
  size="$(wc -c < "$file" 2>/dev/null | tr -d ' ')"
  case "$size" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$size" -gt "$max" ]; then
    tail -c "$((max / 2))" "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file"
  fi
  return 0
}

# Every hook exits 0 in silence by design, which is right for safety and
# terrible for support. NOTIFY_DEBUG=1 leaves a trail without changing any
# behaviour: one line per call, appended to .debug.log next to the skill.
debug_log() {
  [ "${NOTIFY_DEBUG:-0}" = "1" ] || return 0
  local dir file
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  file="$dir/.debug.log"
  rotate_log "$file"
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${1:-?}" "${2:-}" >> "$file"
  return 0
}

# printf into a variable-free string: say <template> [args...]
say() {
  local fmt="$1"; shift
  # shellcheck disable=SC2059  # the template IS the format string here
  printf "$fmt" "$@"
}

# Returns 0 when the frontmost app is an editor/terminal. Extend the list via
# NOTIFY_FRONT_APPS (comma-separated lsappinfo names); NOTIFY_FORCE=1 bypasses
# the gate entirely (used for testing). Callers want is_user_watching, which
# also knows when nobody is at the keyboard.
front_is_editor() {
  [ "${NOTIFY_FORCE:-0}" = "1" ] && return 1
  local front
  front="$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
    | sed -E 's/.*"(LSDisplayName|name)"="([^"]+)".*/\2/')"
  case "$front" in
    Code|"Visual Studio Code"|"Code - Insiders"|Cursor|Windsurf|Zed|Terminal|iTerm2|kitty|Ghostty|WezTerm|Alacritty|Warp|Hyper|Tabby)
      return 0 ;;
  esac
  if [ -n "$front" ] && [ -n "${NOTIFY_FRONT_APPS:-}" ]; then
    case ",$NOTIFY_FRONT_APPS," in
      *",$front,"*) return 0 ;;
    esac
  fi
  return 1
}

# Seconds since the last keyboard or mouse input, from the HID system (needs no
# permission). Prints nothing when it cannot be read.
idle_secs() {
  local io
  io="$(command -v ioreg 2>/dev/null)" || io=/usr/sbin/ioreg
  "$io" -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }'
}

# No input for NOTIFY_AWAY_SECS (default 60): whatever app is in front, nobody
# is looking at it. An unreadable idle time never counts as away.
is_away() {
  local idle
  idle="$(idle_secs)"
  case "$idle" in ''|*[!0-9]*) return 1 ;; esac
  [ "$idle" -ge "${NOTIFY_AWAY_SECS:-60}" ] 2>/dev/null
}

# True when the user is plausibly looking at Claude Code right now: an editor
# or terminal in front AND someone at the keyboard. "Done" banners and approval
# dialogs are noise then; the editor left in front during a coffee break is
# exactly when they matter.
is_user_watching() {
  [ "${NOTIFY_FORCE:-0}" = "1" ] && return 1
  is_away && return 1
  front_is_editor
}

# One permission request raises PermissionRequest (approval-hook.sh) and, after
# about six seconds of waiting, Notification/permission_prompt (notify-hook.sh).
# Whichever announces it leaves a per-session stamp, so the other one keeps
# quiet: one banner and one sonar per request.
announced_file() {
  printf '%s/.announced-%s' "$NOTIFY_STATE_DIR" "$(printf '%s' "${1:-unknown}" | tr -c 'A-Za-z0-9_-' '_')"
}

mark_announced() {
  mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null || return 0
  date +%s > "$(announced_file "$1")" 2>/dev/null || true
}

clear_announced() {
  rm -f "$(announced_file "$1")" 2>/dev/null
  return 0
}

# usage: announced_recently <session_id> <max_age_secs>
announced_recently() {
  local file at
  file="$(announced_file "$1")"
  [ -f "$file" ] || return 1
  at="$(cat "$file" 2>/dev/null)"
  case "$at" in ''|*[!0-9]*) return 1 ;; esac
  [ $(( $(date +%s) - at )) -lt "${2:-120}" ]
}

# Shows a native dialog and prints the chosen token — empty when the user
# closed it, it timed out, or anything failed at all. Callers must treat an
# empty answer as "do nothing".
#
# The timeout lives here rather than in the dialog because a scheduled NSTimer
# never fires inside a modal run loop. And the watchdog MUST NOT inherit our
# stdout: a command substitution upstream stays blocked until every writer
# closes the pipe, which would hold the answer hostage for the full timeout
# after the user already clicked.
#
# <detail> is shown verbatim in a scrollable monospaced box under the body:
# the exact command someone is about to approve.
#
# usage: run_dialog <title> <body> <icon> <buttons> [timeout_secs] [detail]
run_dialog() {
  local title="$1" body="$2" icon="$3" buttons="$4" timeout="${5:-50}" detail="${6:-}"
  local dir out flag pid watchdog res
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  out="$(mktemp)"
  flag="$out.timeout"

  osascript -l JavaScript "$dir/dialog.js" "$title" "$body" "$icon" "$buttons" "$detail" >"$out" 2>/dev/null &
  pid=$!
  ( sleep "$timeout"; : > "$flag"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" 2>/dev/null
  { kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null; } 2>/dev/null

  # A dialog torn down mid-flight can still flush a token (AppKit unwinds the
  # modal session as the process dies). A timeout is never an answer.
  if [ -f "$flag" ]; then res=""; else res="$(cat "$out")"; fi
  rm -f "$out" "$flag"
  printf '%s' "$res"
}

# Path of the terminal-notifier.app behind the installed CLI. Two layouts exist
# in the wild: the binary may sit inside the bundle itself
# (<...>.app/Contents/MacOS/terminal-notifier), or — current Homebrew — `bin/`
# holds a shell wrapper that execs the bundle sitting beside it in the keg.
# Prints the path, or returns 1 when it cannot be resolved.
brew_bundle() {
  local bin app
  command -v terminal-notifier >/dev/null 2>&1 || return 1
  bin="$(readlink -f "$(command -v terminal-notifier)")"
  app="${bin%/Contents/MacOS/*}"
  case "$app" in
    *.app) ;;
    *)
      app="$(sed -nE 's|.*"([^"]*\.app)/Contents/MacOS/[^"]*".*|\1|p' "$bin" 2>/dev/null | head -1)"
      [ -n "$app" ] && [ -d "$app" ] || app="$(dirname "$(dirname "$bin")")/terminal-notifier.app"
      ;;
  esac
  [ -d "$app" ] || return 1
  printf '%s' "$app"
}

# The bundle the Claude icon belongs to: the dedicated app when it exists,
# otherwise whatever terminal-notifier the machine has.
icon_target_bundle() {
  if [ -d "$DEDICATED_APP" ]; then
    printf '%s' "$DEDICATED_APP"
  else
    brew_bundle
  fi
}
