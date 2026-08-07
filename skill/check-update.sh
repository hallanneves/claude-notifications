#!/bin/bash
# check-update.sh — is there a newer tagged version upstream?
#
# Posts a clickable banner when there is; clicking it runs update.sh. Silent
# otherwise: no banner for "you are up to date" unless asked explicitly.
#
# usage: check-update.sh            # rate-limited (once a day), for hooks
#        check-update.sh --force    # check now, and report either outcome
#
# Reads no argument beyond that. Disable entirely with NOTIFY_UPDATE_CHECK=0.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

[ "$FORCE" = 0 ] && [ "${NOTIFY_UPDATE_CHECK:-1}" = "0" ] && exit 0
command -v git >/dev/null 2>&1 || exit 0

STAMP="$DIR/.update-check"
NOW="$(date +%s)"

# The stamp is written before the network call, so a hanging or failing check
# still costs at most one attempt per interval.
if [ "$FORCE" = 0 ] && [ -f "$STAMP" ]; then
  LAST="$(cat "$STAMP" 2>/dev/null)"
  case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
  [ "$((NOW - LAST))" -lt "${NOTIFY_UPDATE_INTERVAL:-86400}" ] && exit 0
fi
echo "$NOW" > "$STAMP"

LOCAL="$(cat "$DIR/VERSION" 2>/dev/null)"
case "$LOCAL" in '') LOCAL="0.0.0" ;; esac

# ls-remote needs no clone, no auth and no JSON parsing.
TAGS="$(git ls-remote --tags --refs "$NOTIFY_UPDATE_REPO" 2>/dev/null)"
if [ -z "$TAGS" ]; then
  [ "$FORCE" = 1 ] && echo "não consegui consultar $NOTIFY_UPDATE_REPO (offline? repo privado?)"
  exit 0
fi

# Two- and three-part tags both count: the repo carries older ones like "0.1".
REMOTE="$(printf '%s\n' "$TAGS" \
  | sed -nE 's|.*refs/tags/v?([0-9]+(\.[0-9]+){1,2})$|\1|p' | sort -V | tail -1)"
if [ -z "$REMOTE" ]; then
  [ "$FORCE" = 1 ] && echo "nenhuma tag de versão em $NOTIFY_UPDATE_REPO"
  exit 0
fi

# Only a strictly newer upstream counts: a local build ahead of the last tag
# (or an equal one) is not an update.
NEWEST="$(printf '%s\n%s\n' "$LOCAL" "$REMOTE" | sort -V | tail -1)"
if [ "$LOCAL" = "$REMOTE" ] || [ "$NEWEST" != "$REMOTE" ]; then
  [ "$FORCE" = 1 ] && echo "já está atualizado (local $LOCAL, remoto $REMOTE)"
  exit 0
fi

echo "atualização disponível: $LOCAL -> $REMOTE"
# Quoted so a $HOME with spaces still resolves to one argument.
NOTIFY_EXECUTE="'$DIR/update.sh'" \
  "$DIR/notify.sh" "Clique para atualizar da $LOCAL para a $REMOTE" \
  "Atualização disponível" "claude-notifications $REMOTE"
