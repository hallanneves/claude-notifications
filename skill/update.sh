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
  "$DIR/notify.sh" --fail "$1" "" "detalhes em $LOG"
  exit 1
}

command -v git >/dev/null 2>&1 || fail "git não encontrado — não dá para atualizar"

BEFORE="$(cat "$DIR/VERSION" 2>/dev/null)"
case "$BEFORE" in '') BEFORE="?" ;; esac

# Browser view of whatever remote we track, ssh or https.
WEB="$(printf '%s' "${NOTIFY_UPDATE_REPO%.git}" \
  | sed -e 's|^git@|https://|' -e 's|^\(https://[^/:]*\):|\1/|')"

if [ "${1:-}" != "--yes" ]; then
  CHOICE="$(run_dialog "Atualização do claude-notifications" \
    "Você tem a versão $BEFORE. Instalar a mais recente de $WEB? Veja o que mudou antes de instalar, se preferir." \
    "$DIR/claude-logo.png" \
    "Instalar:i:install|Ver no GitHub:g:github|Cancelar (Esc):esc:cancel" \
    "${NOTIFY_DIALOG_TIMEOUT:-120}")"
  case "$CHOICE" in
    install) ;;
    github)
      open "$WEB/releases" 2>/dev/null || open "$WEB" 2>/dev/null || true
      echo "abri $WEB/releases — rode de novo quando quiser instalar"
      exit 0 ;;
    *)
      # Cancel, Esc, timeout or any failure: never install by accident.
      echo "atualização cancelada"
      exit 0 ;;
  esac
fi

SRC="$(cat "$DIR/.source-repo" 2>/dev/null)"
if [ -n "$SRC" ] && [ -d "$SRC/.git" ]; then
  REPO="$SRC"
  if ! git -C "$REPO" pull --ff-only >>"$LOG" 2>&1; then
    fail "não consegui atualizar o clone em $REPO (commits locais ou mudanças não commitadas?)"
  fi
else
  TMP="$(mktemp -d)"
  REPO="$TMP/claude-notifications"
  git clone --depth 1 "$NOTIFY_UPDATE_REPO" "$REPO" >>"$LOG" 2>&1 \
    || fail "não consegui clonar $NOTIFY_UPDATE_REPO"
fi

"$REPO/install.sh" >>"$LOG" 2>&1 || fail "o instalador falhou — veja $LOG"

AFTER="$(cat "$DIR/VERSION" 2>/dev/null)"
case "$AFTER" in '') AFTER="?" ;; esac

# The check stamp is stale now: a fresh install should be free to look again.
rm -f "$DIR/.update-check"

if [ "$BEFORE" = "$AFTER" ]; then
  MSG="Já estava na versão $AFTER"
else
  MSG="Atualizado da $BEFORE para a $AFTER"
fi
echo "$MSG"
"$DIR/notify.sh" --done "$MSG — reinicie o Claude Code para recarregar os hooks"
