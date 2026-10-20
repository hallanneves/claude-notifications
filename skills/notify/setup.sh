#!/bin/bash
# setup.sh — what the plugin needs outside Claude Code, once per version:
#  - the notifier app, which posts the banners and carries their permission
#    and the Claude icon (install-notifier-app.sh);
#  - the VSCode bridge, which lets a click reach the exact Claude tab or
#    integrated terminal (vscode-bridge/), in code and cursor when present.
#
# session-hook.sh runs it detached the first time a session starts on a new
# version; install.sh runs it in the foreground. Safe to re-run by hand.
# NOTIFY_BRIDGE=0 (notify.conf) skips the bridge.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
# shellcheck source=notify-lib.sh
. "$DIR/notify-lib.sh"
load_notify_conf
with_tool_path

mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null
# Two sessions starting together would both get here: the second one leaves.
# A lock older than 10 minutes was left by a run that died.
LOCK="$NOTIFY_STATE_DIR/.setup.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ] || exit 0
  rmdir "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if command -v terminal-notifier >/dev/null 2>&1; then
  "$ROOT/install-notifier-app.sh" || echo "⚠️  $L_INS_APP_FAIL"
else
  echo "ℹ️  $L_INS_TN_HINT"
  echo "$L_INS_TN_HINT2"
fi

# Installed only when its version changed: --install-extension takes seconds.
install_bridge() {
  local cli="$1" want have tmp
  command -v "$cli" >/dev/null 2>&1 || return 0
  want="hallanneves.claude-notify-bridge@$(jq -r .version "$ROOT/vscode-bridge/package.json")"
  have="$("$cli" --list-extensions --show-versions 2>/dev/null \
    | grep -i '^hallanneves\.claude-notify-bridge@' || true)"
  if [ "$(printf '%s' "$have" | tr '[:upper:]' '[:lower:]')" = "$want" ]; then
    printf '✅ '; say "$L_INS_BRIDGE_PRESENT" "$cli"
    return 0
  fi
  tmp="$(mktemp -d)"
  if "$ROOT/vscode-bridge/build-vsix.sh" "$tmp/claude-notify-bridge.vsix" \
    && "$cli" --install-extension "$tmp/claude-notify-bridge.vsix" --force >/dev/null 2>&1; then
    printf '✅ '; say "$L_INS_BRIDGE_OK" "$cli"
  else
    printf '⚠️  '; say "$L_INS_BRIDGE_FAIL" "$cli"
  fi
  rm -rf "$tmp"
}
if [ "${NOTIFY_BRIDGE:-1}" != "0" ]; then
  install_bridge code
  install_bridge cursor
fi

cp "$ROOT/VERSION" "$NOTIFY_STATE_DIR/.setup-version"
