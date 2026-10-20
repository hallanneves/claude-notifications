#!/bin/bash
# Installer for the /notify skill + notification hooks (Claude Code, macOS).
# Safe to re-run: hooks already pointing at the skill are left alone, hooks
# from other tools are never overwritten (per-event manual-merge warning).
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=skill/notify-lib.sh
. ./skill/notify-lib.sh
load_notify_conf

if [ "$(uname)" != "Darwin" ]; then
  echo "❌ $L_INS_NEED_MACOS"
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "❌ $L_INS_NEED_JQ"; exit 1; }

DEST="$HOME/.claude/skills/notify"
mkdir -p "$DEST"
cp -f skill/SKILL.md skill/notify.conf.example skill/*.sh skill/*.js "$DEST/"
mkdir -p "$DEST/lang"
cp -f skill/lang/*.sh "$DEST/lang/"
# The approval dialog sets this as its NSAlert icon; without it the alert
# borrows osascript's generic document icon.
cp -f assets/claude-logo.png "$DEST/claude-logo.png"
cp -f VERSION "$DEST/VERSION"
# update.sh installs from a throwaway clone of the advertised tag, so the path
# this was installed from is no longer recorded (older installs left one).
rm -f "$DEST/.source-repo"
chmod +x "$DEST"/*.sh
printf '✅ '; say "$L_INS_SKILL_OK" "$DEST"
say "$L_INS_CONF_HINT" "$DEST/notify.conf.example"

SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# One timestamped backup per run, taken only if we are about to modify.
BACKUP=""
ensure_backup() {
  [ -n "$BACKUP" ] && return 0
  BACKUP="${SETTINGS}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
}

MANUAL=""
for EV in Notification Stop PermissionRequest UserPromptSubmit; do
  if ! jq -e --arg ev "$EV" '.hooks[$ev]' "$SETTINGS" >/dev/null 2>&1; then
    ensure_backup
    tmp="$(mktemp)"
    jq -s --arg ev "$EV" \
      '.[0].hooks = ((.[0].hooks // {}) + {($ev): .[1].hooks[$ev]}) | .[0]' \
      "$SETTINGS" hooks.json > "$tmp"
    jq -e . "$tmp" >/dev/null
    mv "$tmp" "$SETTINGS"
    printf '✅ '; say "$L_INS_HOOK_ADDED" "$EV" "$SETTINGS"
  elif jq -e --arg ev "$EV" '.hooks[$ev] | tostring | contains("/skills/notify/")' "$SETTINGS" >/dev/null 2>&1; then
    printf '✅ '; say "$L_INS_HOOK_PRESENT" "$EV"
  else
    MANUAL="$MANUAL $EV"
  fi
done
if [ -n "$MANUAL" ]; then
  printf '⚠️  '; say "$L_INS_HOOK_MANUAL" "$MANUAL"
  echo "$L_INS_HOOK_MANUAL2"
fi
[ -n "$BACKUP" ] && say "$L_INS_BACKUP" "$BACKUP"

if command -v terminal-notifier >/dev/null 2>&1; then
  ./install-notifier-app.sh || echo "⚠️  $L_INS_APP_FAIL"
else
  echo "ℹ️  $L_INS_TN_HINT"
  echo "$L_INS_TN_HINT2"
fi

# The editor bridge (vscode-bridge/): what lets a click reach the exact Claude
# tab or integrated terminal instead of just the project's window. Installed
# into each editor whose CLI is on PATH, and only when its version changed.
# NOTIFY_BRIDGE=0 skips it.
install_bridge() {
  local cli="$1" want have tmp
  command -v "$cli" >/dev/null 2>&1 || return 0
  want="hallanneves.claude-notify-bridge@$(jq -r .version vscode-bridge/package.json)"
  have="$("$cli" --list-extensions --show-versions 2>/dev/null \
    | grep -i '^hallanneves\.claude-notify-bridge@' || true)"
  if [ "$(printf '%s' "$have" | tr '[:upper:]' '[:lower:]')" = "$want" ]; then
    printf '✅ '; say "$L_INS_BRIDGE_PRESENT" "$cli"
    return 0
  fi
  tmp="$(mktemp -d)"
  if ./vscode-bridge/build-vsix.sh "$tmp/claude-notify-bridge.vsix" \
    && "$cli" --install-extension "$tmp/claude-notify-bridge.vsix" --force >/dev/null 2>&1; then
    printf '✅ '; say "$L_INS_BRIDGE_OK" "$cli"
    echo "$L_INS_BRIDGE_RELOAD"
  else
    printf '⚠️  '; say "$L_INS_BRIDGE_FAIL" "$cli"
  fi
  rm -rf "$tmp"
}
if [ "${NOTIFY_BRIDGE:-1}" != "0" ]; then
  install_bridge code
  install_bridge cursor
fi

echo
printf '🔔 '; say "$L_INS_TEST" "$DEST"
echo "➡️  $L_INS_RESTART"
echo "➡️  $L_INS_NO_BANNER"
echo "$L_INS_NO_BANNER2"
