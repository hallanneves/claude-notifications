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

# Runtime state (mute stamp, reminder pids, per-session stamps, logs) lives
# outside the code: an install or update replaces the skill directory, and
# state kept there was lost with it. Inside a Claude Code plugin it goes to the
# plugin's data dir, which survives updates. NOTIFY_STATE_DIR overrides.
if [ -z "${NOTIFY_STATE_DIR:-}" ]; then
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    NOTIFY_STATE_DIR="$CLAUDE_PLUGIN_DATA"
  else
    NOTIFY_STATE_DIR="$HOME/Library/Application Support/claude-notifications"
  fi
fi
MUTE_FILE="${MUTE_FILE:-$NOTIFY_STATE_DIR/.mute-until}"

# Versions up to 1.7 kept their state next to the skill. Moved once, on the
# first run that finds no state directory, so an active mute or a running
# reminder survives the upgrade.
migrate_legacy_state() {
  local legacy="$HOME/.claude/skills/notify" f
  mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null || return 0
  [ -d "$legacy" ] || return 0
  for f in "$legacy"/.mute-until "$legacy"/.repeat.pids "$legacy"/.update-check \
    "$legacy"/.update.log "$legacy"/.debug.log "$legacy"/.announced-* "$legacy"/.tcc-hint-*; do
    [ -f "$f" ] && mv -n "$f" "$NOTIFY_STATE_DIR/" 2>/dev/null
  done
  return 0
}

# Optional user config, shared by every script that sources this lib.
load_notify_conf() {
  # shellcheck disable=SC1090,SC1091
  [ -f "$HOME/.claude/skills/notify/notify.conf" ] && . "$HOME/.claude/skills/notify/notify.conf"
  : "${NOTIFY_UPDATE_REPO:=$NOTIFY_UPDATE_REPO_DEFAULT}"
  [ -d "$NOTIFY_STATE_DIR" ] || migrate_legacy_state
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

# The bundle id of an .app directory.
bundle_id_of() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null
}

# Walks up from <pid> through a `ps -axo pid=,ppid=,tty=,comm=` table to the
# nearest thing hosting it, and prints "<kind> <bundle id>". Kinds: herdr and
# tmux (multiplexers: their servers are daemons, so no app above them),
# editor-extension (an editor's extension host, e.g. the Claude panel),
# editor-terminal (an editor's integrated terminal), app (any other app, e.g.
# Terminal or iTerm2). Prints nothing when the walk finds none of these.
host_above() {
  local table="$1" pid="$2" hops=0 line p pp tty comm bundle
  while [ "$hops" -lt 40 ]; do
    line="$(printf '%s\n' "$table" | awk -v p="$pid" '$1 == p { print; exit }')"
    [ -n "$line" ] || return 0
    read -r p pp tty comm <<< "$line"
    case "${comm##*/}" in
      herdr) printf 'herdr '; return 0 ;;
      tmux*) printf 'tmux '; return 0 ;;
    esac
    case "$comm" in
      *.app/Contents/*)
        # The outermost bundle: a helper app nests inside its editor's.
        bundle="$(bundle_id_of "${comm%%.app/*}.app")"
        case "$comm" in
          *"Helper (Plugin)"*) printf 'editor-extension %s' "$bundle" ;;
          *) if is_editor_bundle "$bundle"; then
               printf 'editor-terminal %s' "$bundle"
             else
               printf 'app %s' "$bundle"
             fi ;;
        esac
        return 0 ;;
    esac
    [ "$pp" -gt 1 ] 2>/dev/null || return 0
    pid="$pp"
    hops=$((hops + 1))
  done
}

# Where this session runs, read from the process tree rather than from the
# environment: multiplexers and terminals leak their variables into everything
# started inside them (herdr inherits the __CFBundleIdentifier of whatever
# started its server), but the nearest ancestor is always the truth. Sets
# ORIGIN_KIND (a host_above kind, or unknown) and ORIGIN_BUNDLE. NOTIFY_PID
# starts the walk elsewhere (tests).
detect_origin() {
  local found
  found="$(host_above "$(ps -axo pid=,ppid=,tty=,comm= 2>/dev/null)" "${NOTIFY_PID:-$$}")"
  ORIGIN_KIND="${found%% *}"
  ORIGIN_BUNDLE="${found#* }"
  [ -n "$ORIGIN_KIND" ] || ORIGIN_KIND="unknown"
  ORIGIN_DONE=1
}

# The app hosting this session: what a click falls back to, so it never lands
# in an app the session has nothing to do with (it used to be VSCode for
# everyone, which launched VSCode for a click on a Terminal session).
# NOTIFY_ACTIVATE (notify.conf or environment) overrides; then the process
# tree; then the terminal naming itself, and the bundle id macOS stamps on
# every process an app launches. Prints nothing when there is no clue at all.
host_bundle() {
  if [ -n "${NOTIFY_ACTIVATE:-}" ]; then
    printf '%s' "$NOTIFY_ACTIVATE"
    return 0
  fi
  [ -n "${ORIGIN_DONE:-}" ] || detect_origin
  if [ -n "${ORIGIN_BUNDLE:-}" ]; then
    printf '%s' "$ORIGIN_BUNDLE"
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

# The herdr CLI. Found from a click too, whose PATH is only /usr/bin:/bin:
# herdr exports its own path into every pane.
herdr_bin() {
  local b
  for b in "${HERDR_BIN_PATH:-}" "$(command -v herdr 2>/dev/null)" \
    /opt/homebrew/bin/herdr /usr/local/bin/herdr; do
    if [ -n "$b" ] && [ -x "$b" ]; then
      printf '%s' "$b"
      return 0
    fi
  done
  return 1
}

# This pane as herdr sees it (JSON), fetched once per hook into
# HERDR_AGENT_JSON. Empty when herdr cannot be asked.
herdr_load() {
  [ -n "${HERDR_AGENT_LOADED:-}" ] && return 0
  HERDR_AGENT_LOADED=1
  HERDR_AGENT_JSON=""
  local bin
  bin="$(herdr_bin)" || return 0
  [ -n "${HERDR_PANE_ID:-}" ] || return 0
  HERDR_AGENT_JSON="$("$bin" agent get "$HERDR_PANE_ID" 2>/dev/null)"
  return 0
}

# Whether this pane is the one herdr shows. When herdr cannot say, the answer
# is yes: the app-level gate already decided, as it did before herdr support.
herdr_pane_focused() {
  herdr_load
  [ -n "$HERDR_AGENT_JSON" ] || return 0
  printf '%s' "$HERDR_AGENT_JSON" | jq -e '.result.agent.focused == true' >/dev/null 2>&1
}

# The session's title as herdr shows it (Claude Code sets the terminal title
# to what the conversation is about). Empty outside herdr.
herdr_session_title() {
  [ "${ORIGIN_KIND:-}" = "herdr" ] || return 0
  herdr_load
  printf '%s' "$HERDR_AGENT_JSON" | jq -r '.result.agent.terminal_title_stripped // empty' 2>/dev/null
  return 0
}

# Everything the click needs, captured while the hook still has it, into the
# FOCUS_ARGS array. NOTIFY_SESSION is the Claude session id, which finds a
# herdr pane even after it moved.
build_focus_args() {
  FOCUS_ARGS=(--cwd "$1" --kind "${ORIGIN_KIND:-unknown}" --host "$(host_bundle)"
    --term-program "${TERM_PROGRAM:-}" --iterm "$(iterm_session)" --tty "$(current_tty)")
  if [ "${ORIGIN_KIND:-}" = "herdr" ]; then
    FOCUS_ARGS+=(--herdr-bin "$(herdr_bin)" --herdr-socket "${HERDR_SOCKET_PATH:-}"
      --herdr-pane "${HERDR_PANE_ID:-}" --session "${NOTIFY_SESSION:-}")
  fi
}

# The click action as a shell command string (terminal-notifier -execute).
focus_cmd() {
  local dir out a
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  build_focus_args "$1"
  out="$(shq "$dir/focus.sh")"
  for a in "${FOCUS_ARGS[@]}"; do
    out="$out $(shq "$a")"
  done
  printf '%s' "$out"
}

# Same thing, run right now instead of baked into a click.
focus_now() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  build_focus_args "$1"
  "$dir/focus.sh" "${FOCUS_ARGS[@]}"
}

# True when a click has somewhere specific to land: a herdr pane or terminal
# session we can name, or a project an editor can focus.
has_focus_target() {
  [ "${ORIGIN_KIND:-}" = "herdr" ] && return 0
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
  local file="$NOTIFY_STATE_DIR/.debug.log"
  mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null
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

# The frontmost app: its display name, and its bundle id.
front_name() {
  lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
    | sed -E 's/.*"(LSDisplayName|name)"="([^"]+)".*/\2/'
}

front_bundle() {
  lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
    | sed -nE 's/.*"CFBundleIdentifier"="([^"]+)".*/\1/p'
}

# Apps the user declared as "I am looking at Claude when this is in front"
# (NOTIFY_FRONT_APPS, comma-separated lsappinfo names).
front_is_extra() {
  local front
  front="$(front_name)"
  [ -n "$front" ] && [ -n "${NOTIFY_FRONT_APPS:-}" ] || return 1
  case ",$NOTIFY_FRONT_APPS," in
    *",$front,"*) return 0 ;;
  esac
  return 1
}

# Returns 0 when the frontmost app is any known editor/terminal: the guess for
# a session whose own app is unknown. NOTIFY_FORCE=1 bypasses the gate
# entirely (used for testing). Callers want is_user_watching.
front_is_editor() {
  [ "${NOTIFY_FORCE:-0}" = "1" ] && return 1
  case "$(front_name)" in
    Code|"Visual Studio Code"|"Code - Insiders"|Cursor|Windsurf|Zed|Terminal|iTerm2|kitty|Ghostty|WezTerm|Alacritty|Warp|Hyper|Tabby)
      return 0 ;;
  esac
  front_is_extra
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

# Terminals running a herdr client, one "<tty> <bundle id>" line each. The
# client's tty is its tab's, and its app is what the client descends from:
# herdr's own environment names whichever terminal happened to start the
# server, not the one on screen.
herdr_clients() {
  local table pid ppid tty comm found
  table="$(ps -axo pid=,ppid=,tty=,comm= 2>/dev/null)"
  while read -r pid ppid tty comm; do
    [ "${comm##*/}" = "herdr" ] && [ -n "$tty" ] && [ "$tty" != "??" ] || continue
    found="$(host_above "$table" "$ppid")"
    [ "${found%% *}" = "app" ] && [ -n "${found#* }" ] || continue
    printf '/dev/%s %s\n' "$tty" "${found#* }"
  done <<< "$table"
}

# The app whose window shows this session: the one that must be in front for
# the user to be looking at it.
session_app() {
  local line
  if [ "${ORIGIN_KIND:-}" = "herdr" ] && [ -z "${NOTIFY_ACTIVATE:-}" ]; then
    line="$(herdr_clients | head -1)"
    if [ -n "$line" ]; then
      printf '%s' "${line#* }"
      return 0
    fi
  fi
  host_bundle
}

# True when the user is plausibly looking at THIS session right now: the app
# showing it in front (any editor or terminal, when that app is unknown), AND
# someone at the keyboard, AND under herdr this session's pane on screen.
# "Done" banners and approval dialogs are noise then. VSCode in front while
# the session runs in Terminal, the editor left in front during a coffee
# break, another herdr pane in view: that is exactly when they matter.
# Call detect_origin first.
is_user_watching() {
  local app
  [ "${NOTIFY_FORCE:-0}" = "1" ] && return 1
  is_away && return 1
  app="$(session_app)"
  if [ -n "$app" ]; then
    [ "$(front_bundle)" = "$app" ] || front_is_extra || return 1
  else
    front_is_editor || return 1
  fi
  if [ "${ORIGIN_KIND:-}" = "herdr" ]; then
    herdr_pane_focused || return 1
  fi
  return 0
}

# A session id made safe for a file name or a notification group.
safe_id() {
  printf '%s' "${1:-unknown}" | tr -c 'A-Za-z0-9_-' '_'
}

# Every notification of one session shares a group, so a new one replaces the
# last instead of piling up, and answering the session clears it.
session_group() {
  printf 'claude-%s' "$(safe_id "$1")"
}

# Per-session timestamps: usage: stamp <name> <session_id>.
#   announced  a permission request already got its banner (approval-hook);
#              PermissionRequest and, after ~6s of waiting, the Notification
#              hook both see the same request, and only one may speak
#   turn       when the user last sent a prompt (prompt-hook)
#   stopped    when the last "done" banner went out (stop-hook)
stamp_file() {
  printf '%s/.%s-%s' "$NOTIFY_STATE_DIR" "$1" "$(safe_id "$2")"
}

stamp() {
  mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null || return 0
  date +%s > "$(stamp_file "$1" "$2")" 2>/dev/null || true
}

unstamp() {
  rm -f "$(stamp_file "$1" "$2")" 2>/dev/null
  return 0
}

# Seconds since the stamp was taken; nothing when there is none.
stamp_age() {
  local file at
  file="$(stamp_file "$1" "$2")"
  [ -f "$file" ] || return 0
  at="$(cat "$file" 2>/dev/null)"
  case "$at" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s' "$(( $(date +%s) - at ))"
}

# usage: stamped_within <name> <session_id> <max_age_secs>
stamped_within() {
  local age
  age="$(stamp_age "$1" "$2")"
  [ -n "$age" ] && [ "$age" -lt "$3" ]
}

# The binary that posts: the dedicated app's copy of terminal-notifier when it
# exists (its own entry in System Settings, and the Claude icon), otherwise
# terminal-notifier from PATH. NOTIFY_TN overrides. Fails when there is none.
notifier_bin() {
  if [ -n "${NOTIFY_TN:-}" ]; then
    printf '%s' "$NOTIFY_TN"
    return 0
  fi
  if [ -x "$DEDICATED_APP/Contents/MacOS/terminal-notifier" ]; then
    printf '%s' "$DEDICATED_APP/Contents/MacOS/terminal-notifier"
    return 0
  fi
  command -v terminal-notifier 2>/dev/null
}

# The first non-blank line of a Markdown answer, as plain text, for a banner.
first_line() {
  jq -Rrs 'split("\n") | map(select(test("\\S"))) | (first // "")
    | sub("^[#>*\\-\\s]+"; "") | gsub("[`*]"; "") | .[0:140]' 2>/dev/null
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
