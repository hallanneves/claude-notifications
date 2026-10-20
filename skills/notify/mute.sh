#!/bin/bash
# mute.sh — silence notifications for a while, for focused work.
#
# usage: mute.sh [duration]   # 45s, 30m, 2h, 1d — a bare number means minutes
#        mute.sh on           # until you turn it back off
#        mute.sh off
#        mute.sh status
#
# Muting covers the banners AND the approval dialog. macOS Focus already hides
# banners, but a modal dialog still steals the screen — and that is exactly the
# interruption you are trying to avoid. While muted, a permission request falls
# back to Claude Code's normal terminal prompt, which waits quietly.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

report_status() {
  local until
  until="$(mute_until)"
  case "$until" in
    '')      echo "$L_MUTE_OFF" ;;
    forever) echo "$L_MUTE_ON_FOREVER" ;;
    *)       say "$L_MUTE_ON_UNTIL" "$(date -r "$until" '+%H:%M')" ;;
  esac
}

# Accepts 45s / 30m / 2h / 1d, or a bare number of minutes. Prints seconds.
parse_duration() {
  local v="$1" n mult
  case "$v" in
    *[0-9]s) n="${v%s}"; mult=1 ;;
    *[0-9]m) n="${v%m}"; mult=60 ;;
    *[0-9]h) n="${v%h}"; mult=3600 ;;
    *[0-9]d) n="${v%d}"; mult=86400 ;;
    *[0-9])  n="$v";     mult=60 ;;
    *) return 1 ;;
  esac
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  [ "$n" -gt 0 ] || return 1
  printf '%s' "$((n * mult))"
}

case "${1:-status}" in
  status)
    report_status
    exit 0 ;;
  off|unmute)
    rm -f "$MUTE_FILE"
    echo "$L_MUTE_OFF"
    exit 0 ;;
  on)
    printf 'forever' > "$MUTE_FILE"
    echo "$L_MUTE_ON_FOREVER"
    exit 0 ;;
esac

SECS="$(parse_duration "$1")" || { say "$L_MUTE_BAD_DURATION" "$1"; exit 1; }
printf '%s' "$(( $(date +%s) + SECS ))" > "$MUTE_FILE"
report_status
