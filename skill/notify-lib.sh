#!/bin/bash
# notify-lib.sh — shared constants and helpers for the notify skill scripts
# (notify.sh, stop-hook.sh, approval-hook.sh) and for the installer scripts at
# the repo root. Meant to be sourced, not executed.
# shellcheck disable=SC2034  # constants are consumed by the sourcing scripts

DEDICATED_APP_NAME="Claude Code Notifier"
DEDICATED_APP="$HOME/Applications/$DEDICATED_APP_NAME.app"
DEDICATED_BUNDLE_ID="com.github.hallanneves.claude-notifier"

# Bundle id focused when a notification is clicked / "Abrir no editor" is
# chosen. NOTIFY_ACTIVATE (notify.conf or environment) overrides.
NOTIFY_ACTIVATE_DEFAULT="com.microsoft.VSCode"

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

# printf into a variable-free string: say <template> [args...]
say() {
  local fmt="$1"; shift
  # shellcheck disable=SC2059  # the template IS the format string here
  printf "$fmt" "$@"
}

# Returns 0 when the frontmost app is an editor/terminal — the user is already
# looking at Claude Code, so "done" banners and approval dialogs are noise.
# Extend the list via NOTIFY_FRONT_APPS (comma-separated lsappinfo names);
# NOTIFY_FORCE=1 bypasses the gate entirely (used for testing).
front_is_editor() {
  [ "${NOTIFY_FORCE:-0}" = "1" ] && return 1
  local front
  front="$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
    | sed -E 's/.*"(LSDisplayName|name)"="([^"]+)".*/\2/')"
  case "$front" in
    Code|"Visual Studio Code"|"Code - Insiders"|Cursor|Windsurf|Zed|Electron|Terminal|iTerm2|kitty|Ghostty|WezTerm|Alacritty|Warp|Hyper|Tabby)
      return 0 ;;
  esac
  if [ -n "$front" ] && [ -n "${NOTIFY_FRONT_APPS:-}" ]; then
    case ",$NOTIFY_FRONT_APPS," in
      *",$front,"*) return 0 ;;
    esac
  fi
  return 1
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
# usage: run_dialog <title> <body> <icon> <buttons> [timeout_secs]
run_dialog() {
  local title="$1" body="$2" icon="$3" buttons="$4" timeout="${5:-50}"
  local dir out flag pid watchdog res
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  out="$(mktemp)"
  flag="$out.timeout"

  osascript -l JavaScript "$dir/dialog.js" "$title" "$body" "$icon" "$buttons" >"$out" 2>/dev/null &
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
