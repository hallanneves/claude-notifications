#!/bin/bash
# update.sh — install the newest tagged claude-notifications.
#
# Wired to the click of the "update available" banner, and safe to run by hand.
# A click never installs anything on its own: it opens a dialog offering
# Install / View on GitHub / Cancel, because this is open source and you are
# entitled to read what you are about to run. `--yes` skips the dialog.
#
# It installs the exact tag it advertised, from a throwaway clone. It never
# touches your own working copy: pulling a branch could deliver unreleased
# commits, and checking out a tag in a clone you work in would leave you on a
# detached HEAD.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf

LOG="$DIR/.update.log"
rotate_log "$LOG"
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

# The newest version-shaped tag, kept as its RAW name so the checkout matches
# whatever convention the repo uses ("v1.3.0" and "0.1" both appear in ours).
TAG="$(git ls-remote --tags --refs "$NOTIFY_UPDATE_REPO" 2>/dev/null \
  | sed -nE 's|.*refs/tags/(v?([0-9]+(\.[0-9]+){1,2}))$|\2 \1|p' \
  | sort -V | tail -1 | cut -d' ' -f2)"
[ -n "$TAG" ] || fail "$(say "$L_UPD_NO_TAGS" "$NOTIFY_UPDATE_REPO")"

if [ "${1:-}" != "--yes" ]; then
  CHOICE="$(run_dialog "$L_UPD_DIALOG_TITLE" \
    "$(say "$L_UPD_DIALOG_BODY" "$BEFORE" "$TAG" "$WEB")" \
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

TMP="$(mktemp -d)"
REPO="$TMP/claude-notifications"
git clone --depth 1 --branch "$TAG" "$NOTIFY_UPDATE_REPO" "$REPO" >>"$LOG" 2>&1 \
  || fail "$(say "$L_UPD_CLONE_FAIL" "$NOTIFY_UPDATE_REPO")"

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
