#!/bin/bash
# migrate.sh — finishes the move from a pre-2.0 install (a copy under
# ~/.claude/skills/notify, hooks written into ~/.claude/settings.json) to the
# plugin, which stands down until then so nothing fires twice.
#  1. the old hook entries leave settings.json (a backup is kept; other
#     tools' hooks stay);
#  2. notify.conf and the state move to the state directory;
#  3. reminders started by the old copy stop: their script is about to go;
#  4. ~/.claude/skills/notify is removed.
#
# usage: migrate.sh [--force]
# Idempotent. Refuses while the plugin is not installed, which would leave no
# notifications at all; --force goes ahead anyway.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

if [ "${1:-}" != "--force" ] && ! plugin_installed; then
  printf '❌ '; say "$L_MIG_NO_PLUGIN" "$PLUGIN_ID"
  exit 1
fi

DID=0
if BACKUP="$(strip_legacy_hooks)"; then
  printf '✅ '; say "$L_MIG_HOOKS" "$HOME/.claude/settings.json" "$BACKUP"
  DID=1
fi

# A reminder is a detached loop calling the copy that started it; the old
# copy's loops carry no "from=" (see repeat.sh), and would tick on in silence
# once their script is gone.
stop_legacy_reminders() {
  local pidfile="$NOTIFY_STATE_DIR/.repeat.pids" keep pid rest cmd
  [ -s "$pidfile" ] || return 0
  keep="$(mktemp)"
  while read -r pid rest; do
    cmd="$(ps -p "$pid" -o command= 2>/dev/null)"
    case "$cmd" in
      *claude-notify-repeat*from=*) echo "$pid $rest" >> "$keep" ;;
      *claude-notify-repeat*)
        kill "$pid" 2>/dev/null && { printf 'ℹ️  '; say "$L_MIG_REMINDER" "$rest"; } ;;
    esac
  done < "$pidfile"
  mv "$keep" "$pidfile"
}

if [ -d "$LEGACY_SKILL_DIR" ]; then
  migrate_legacy_state
  if [ -f "$LEGACY_SKILL_DIR/notify.conf" ]; then
    if [ -f "$NOTIFY_CONF" ]; then
      cp "$LEGACY_SKILL_DIR/notify.conf" "$NOTIFY_CONF.legacy"
      printf 'ℹ️  '; say "$L_MIG_CONF_KEPT" "$NOTIFY_CONF" "$NOTIFY_CONF.legacy"
    else
      mv "$LEGACY_SKILL_DIR/notify.conf" "$NOTIFY_CONF"
      printf '✅ '; say "$L_MIG_CONF_MOVED" "$NOTIFY_CONF"
    fi
  fi
  stop_legacy_reminders
  rm -rf "$LEGACY_SKILL_DIR"
  printf '✅ '; say "$L_MIG_REMOVED" "$LEGACY_SKILL_DIR"
  DID=1
fi

if [ "$DID" = 1 ]; then
  echo "➡️  $L_MIG_RESTART"
else
  echo "$L_MIG_NOTHING"
fi
