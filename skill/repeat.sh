#!/bin/bash
# repeat.sh — fire a macOS notification every N seconds, detached from the session.
# usage: repeat.sh INTERVAL_SECONDS "message" ["title"]
#        repeat.sh stop      # kill all active reminders (only processes we own)
#        repeat.sh list      # show active reminders and prune dead entries
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$DIR/.repeat.pids"
MARKER="claude-notify-repeat"

# A pidfile entry may outlive the process (reboot recycles PIDs), so never act
# on a PID without confirming it is still one of ours via the argv marker.
is_ours() { ps -p "$1" -o command= 2>/dev/null | grep -q "$MARKER"; }

case "${1:?usage: repeat.sh SECONDS MESSAGE [TITLE] | stop | list}" in
  stop)
    if [ -s "$PIDFILE" ]; then
      while read -r pid rest; do
        if is_ours "$pid" && kill "$pid" 2>/dev/null; then
          echo "stopped reminder pid $pid"
        fi
      done < "$PIDFILE"
      : > "$PIDFILE"
    else
      echo "no active reminders"
    fi
    exit 0
    ;;
  list)
    ACTIVE=0
    if [ -s "$PIDFILE" ]; then
      TMP="$(mktemp)"
      while read -r pid rest; do
        if is_ours "$pid"; then
          echo "pid $pid — $rest"
          echo "$pid $rest" >> "$TMP"
          ACTIVE=1
        fi
      done < "$PIDFILE"
      mv "$TMP" "$PIDFILE"
    fi
    [ "$ACTIVE" = 1 ] || echo "no active reminders"
    exit 0
    ;;
esac

INT="$1"
MSG="${2:?usage: repeat.sh SECONDS MESSAGE [TITLE]}"
TITLE="${3:-Lembrete}"

# Reject non-numeric or tiny intervals: a failing/instant sleep would turn the
# loop into a notification firehose.
case "$INT" in
  ''|*[!0-9]*) echo "intervalo inválido: '$INT' (use segundos, inteiro >= 5)"; exit 1 ;;
esac
[ "$INT" -ge 5 ] || { echo "intervalo mínimo é 5s (recebi ${INT}s)"; exit 1; }

nohup env NOTIFY_BIN="$DIR/notify.sh" NOTIFY_MSG="$MSG" NOTIFY_TITLE="$TITLE" NOTIFY_INT="$INT" \
  bash -c "# $MARKER
while true; do sleep \"\$NOTIFY_INT\"; \"\$NOTIFY_BIN\" \"\$NOTIFY_MSG\" \"\$NOTIFY_TITLE\"; done" \
  >/dev/null 2>&1 &
PID=$!
echo "$PID every ${INT}s: $MSG" >> "$PIDFILE"
echo "reminder started: pid $PID, every ${INT}s — stop with: repeat.sh stop"
