#!/bin/bash
# Shared bundle resolution for set-claude-icon.sh and install-notifier-app.sh.
# Meant to be sourced, not executed.

# skill/notify.sh repeats this path literally — it is installed to
# ~/.claude/skills/notify/ and cannot source this file. Keep both in sync.
DEDICATED_APP_NAME="Claude Code Notifier"
DEDICATED_APP="$HOME/Applications/$DEDICATED_APP_NAME.app"
DEDICATED_BUNDLE_ID="com.github.hallanneves.claude-notifier"

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
