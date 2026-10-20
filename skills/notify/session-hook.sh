#!/bin/bash
# SessionStart hook (plugin only): the two things a plugin install cannot do
# by itself.
#  - A pre-2.0 install still has its hooks in ~/.claude/settings.json: the
#    plugin stands down (see plugin_yields) and says how to finish the move.
#  - This version is not set up yet: setup.sh runs detached, so the session
#    never waits on codesign or an editor's CLI.
# Says so through systemMessage, at most once per start, and once ever for the
# auto-update hint. Fails silent, like every hook here.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf
cat >/dev/null 2>&1

MSG=""
add() { MSG="${MSG:+$MSG
}$1"; }

if legacy_hooks_present; then
  add "$L_SES_LEGACY"
else
  mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null
  if setup_needed "$ROOT"; then
    LOG="$NOTIFY_STATE_DIR/.setup.log"
    rotate_log "$LOG"
    ( "$DIR/setup.sh" >>"$LOG" 2>&1 & ) 2>/dev/null
    add "$(say "$L_SES_SETUP" "$(cat "$ROOT/VERSION" 2>/dev/null)" "$LOG")"
  fi
  HINT="$NOTIFY_STATE_DIR/.autoupdate-hint"
  if [ ! -f "$HINT" ] && autoupdate_off; then
    add "$(say "$L_SES_AUTOUPDATE" "$MARKETPLACE_NAME")"
    : > "$HINT"
  fi
fi

[ -n "$MSG" ] && jq -cn --arg m "$MSG" '{systemMessage: $m}'
exit 0
