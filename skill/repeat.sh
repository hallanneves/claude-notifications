#!/bin/bash
# repeat.sh — fire a macOS notification every N seconds, detached from the session.
# usage: repeat.sh INTERVAL_SECONDS "message" ["title"]
#        repeat.sh stop      # kill all active reminders
#        repeat.sh list      # show active reminders
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$DIR/.repeat.pids"

case "${1:?usage: repeat.sh SECONDS MESSAGE [TITLE] | stop | list}" in
  stop)
    if [ -s "$PIDFILE" ]; then
      while read -r pid _; do
        kill "$pid" 2>/dev/null && echo "stopped reminder pid $pid" || true
      done < "$PIDFILE"
      : > "$PIDFILE"
    else
      echo "no active reminders"
    fi
    exit 0
    ;;
  list)
    if [ -s "$PIDFILE" ]; then
      while read -r pid rest; do
        if kill -0 "$pid" 2>/dev/null; then
          echo "pid $pid — $rest"
        fi
      done < "$PIDFILE"
    else
      echo "no active reminders"
    fi
    exit 0
    ;;
esac

INT="$1"
MSG="${2:?usage: repeat.sh SECONDS MESSAGE [TITLE]}"
TITLE="${3:-⏰ Lembrete}"

nohup env NOTIFY_BIN="$DIR/notify.sh" NOTIFY_MSG="$MSG" NOTIFY_TITLE="$TITLE" NOTIFY_INT="$INT" \
  bash -c 'while true; do sleep "$NOTIFY_INT"; "$NOTIFY_BIN" "$NOTIFY_MSG" "$NOTIFY_TITLE"; done' \
  >/dev/null 2>&1 &
PID=$!
echo "$PID every ${INT}s: $MSG" >> "$PIDFILE"
echo "reminder started: pid $PID, every ${INT}s — stop with: repeat.sh stop"
