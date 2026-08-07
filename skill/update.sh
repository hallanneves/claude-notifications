#!/bin/bash
# update.sh — pull the newest claude-notifications and reinstall it.
#
# Wired to the click of the "Atualização disponível" banner, and safe to run by
# hand. A click never installs anything on its own: it opens a dialog offering
# Instalar / Ver no GitHub / Cancelar, because this is open source and you are
# entitled to read what you are about to run. `--yes` skips the dialog.
#
# Prefers the clone the skill was installed from (recorded at install time);
# falls back to a shallow clone of the canonical repo. Never forces anything:
# a clone with local commits or uncommitted work fails the fast-forward and is
# reported, not rewritten.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

LOG="$DIR/.update.log"
TMP=""
trap '[ -n "$TMP" ] && rm -rf "$TMP"' EXIT

fail() {
  echo "$1" >&2
  "$DIR/notify.sh" --fail "$1" "" "$(say "$L_UPD_DETAILS" "$LOG")"
  exit 1
}

command -v git >/dev/null 2>&1 || fail "$L_UPD_NO_GIT"

BEFORE="$(cat "$DIR/VERSION" 2>/dev/null)"
case "$BEFORE" in '') BEFORE="?" ;; esac

# Browser view of whatever remote we track, ssh or https.
WEB="$(printf '%s' "${NOTIFY_UPDATE_REPO%.git}" \
  | sed -e 's|^git@|https://|' -e 's|^\(https://[^/:]*\):|\1/|')"

if [ "${1:-}" != "--yes" ]; then
  CHOICE="$(run_dialog "$L_UPD_DIALOG_TITLE" \
    "$(say "$L_UPD_DIALOG_BODY" "$BEFORE" "$WEB")" \
    "$DIR/claude-logo.png" \
    "$L_UPD_DIALOG_BUTTONS" \
    "${NOTIFY_DIALOG_TIMEOUT:-120}")"
  case "$CHOICE" in
    install) ;;
    github)
      open "$WEB/releases" 2>/dev/null || open "$WEB" 2>/dev/null || true
      say "$L_UPD_OPENED" "$WEB/releases"
      exit 0 ;;
    *)
      # Cancel, Esc, timeout or any failure: never install by accident.
      echo "$L_UPD_CANCELLED"
      exit 0 ;;
  esac
fi

SRC="$(cat "$DIR/.source-repo" 2>/dev/null)"
if [ -n "$SRC" ] && [ -d "$SRC/.git" ]; then
  REPO="$SRC"
  if ! git -C "$REPO" pull --ff-only >>"$LOG" 2>&1; then
    fail "$(say "$L_UPD_PULL_FAIL" "$REPO")"
  fi
else
  TMP="$(mktemp -d)"
  REPO="$TMP/claude-notifications"
  git clone --depth 1 "$NOTIFY_UPDATE_REPO" "$REPO" >>"$LOG" 2>&1 \
    || fail "$(say "$L_UPD_CLONE_FAIL" "$NOTIFY_UPDATE_REPO")"
fi

"$REPO/install.sh" >>"$LOG" 2>&1 || fail "$(say "$L_UPD_INSTALL_FAIL" "$LOG")"

AFTER="$(cat "$DIR/VERSION" 2>/dev/null)"
case "$AFTER" in '') AFTER="?" ;; esac

# The check stamp is stale now: a fresh install should be free to look again.
rm -f "$DIR/.update-check"

if [ "$BEFORE" = "$AFTER" ]; then
  MSG="$(say "$L_UPD_SAME" "$AFTER")"
else
  MSG="$(say "$L_UPD_DONE" "$BEFORE" "$AFTER")"
fi
echo "$MSG"
# The installer just replaced the catalogue: reload so the banner speaks the
# language the NEW version ships, not the one that started the update.
load_lang
"$DIR/notify.sh" --done "$(say "$L_UPD_RESTART" "$MSG")"
