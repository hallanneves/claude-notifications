#!/bin/bash
# install.sh — installs claude-notifications as a Claude Code plugin, sets up
# what it needs outside Claude Code, and retires a pre-2.0 install.
#
# Since 2.0 the plugin system installs and updates it; this only drives the
# `claude` CLI, so it also runs unattended: a 1.x install updates itself by
# running the new tag's install.sh from a throwaway clone.
#
# usage: install.sh           # the plugin from GitHub (hallanneves/claude-notifications)
#        install.sh --local   # from this checkout, loaded in place (development)
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=skills/notify/notify-lib.sh
. ./skills/notify/notify-lib.sh
load_notify_conf
with_tool_path

if [ "$(uname)" != "Darwin" ]; then
  echo "❌ $L_INS_NEED_MACOS"
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "❌ $L_INS_NEED_JQ"; exit 1; }

# A checkout under a throwaway clone would vanish; only --local points here.
SOURCE="$PLUGIN_REPO"
[ "${1:-}" = "--local" ] && SOURCE="$PWD"

CLAUDE="$(claude_bin)" || {
  echo "❌ $L_INS_NO_CLAUDE"
  say "$L_INS_MANUAL" "$PLUGIN_NAME" "$PLUGIN_REPO"
  exit 1
}

# Nothing of the old install is touched before the plugin is in: a failure
# here leaves it working.
if ! "$CLAUDE" plugin install "$PLUGIN_NAME" --marketplace "$SOURCE" --scope user; then
  printf '❌ '; say "$L_INS_PLUGIN_FAIL" "$PLUGIN_ID"
  say "$L_INS_MANUAL" "$PLUGIN_NAME" "$PLUGIN_REPO"
  exit 1
fi
printf '✅ '; say "$L_INS_PLUGIN_OK" "$PLUGIN_ID" "$SOURCE"

./skills/notify/setup.sh || true
./skills/notify/migrate.sh || true

# A 1.x install runs this from a click, with no terminal to read: the banner
# is the only report it gets.
./skills/notify/notify.sh --done "$(say "$L_INS_DONE" "$(cat VERSION)")" >/dev/null 2>&1 || true

echo
echo "➡️  $L_INS_RESTART"
echo "➡️  $L_INS_NO_BANNER"
echo "$L_INS_NO_BANNER2"
