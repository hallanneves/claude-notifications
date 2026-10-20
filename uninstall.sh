#!/bin/bash
# Uninstaller: the plugin (through the `claude` CLI), what a pre-2.0 install
# left (hook entries in ~/.claude/settings.json, its copy of the skill), the
# notifier app, the VSCode bridge and the state. Hook entries that belong to
# other tools are preserved untouched.
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=skills/notify/notify-lib.sh
. ./skills/notify/notify-lib.sh
load_notify_conf
with_tool_path

if CLAUDE="$(claude_bin)"; then
  if plugin_installed && "$CLAUDE" plugin uninstall "$PLUGIN_ID" -y >/dev/null 2>&1; then
    printf '✅ '; say "$L_UNI_PLUGIN_REMOVED" "$PLUGIN_ID"
  fi
  if [ -n "$(marketplace_field .source.source)" ]; then
    "$CLAUDE" plugin marketplace remove "$MARKETPLACE_NAME" >/dev/null 2>&1 || true
  fi
fi

if BACKUP="$(strip_legacy_hooks)"; then
  printf '✅ '; say "$L_UNI_HOOKS_REMOVED" "$HOME/.claude/settings.json" "$BACKUP"
fi

# Stop active reminders before their scripts disappear.
./skills/notify/repeat.sh stop >/dev/null 2>&1 || true

if [ -d "$LEGACY_SKILL_DIR" ]; then
  rm -rf "$LEGACY_SKILL_DIR"
  echo "✅ $L_UNI_SKILL_REMOVED"
fi

# Runtime state and config: only the default location, never a directory
# someone pointed NOTIFY_STATE_DIR at.
STATE_DEFAULT="$HOME/Library/Application Support/claude-notifications"
if [ -d "$STATE_DEFAULT" ]; then
  rm -rf "$STATE_DEFAULT"
fi

# The editor bridge, from every editor that has it.
for cli in code cursor; do
  command -v "$cli" >/dev/null 2>&1 || continue
  if "$cli" --list-extensions 2>/dev/null | grep -qi '^hallanneves\.claude-notify-bridge$'; then
    "$cli" --uninstall-extension hallanneves.claude-notify-bridge >/dev/null 2>&1 \
      && { printf '✅ '; say "$L_UNI_BRIDGE_REMOVED" "$cli"; }
  fi
done

if [ -d "$DEDICATED_APP" ]; then
  rm -rf "$DEDICATED_APP"
  printf '✅ '; say "$L_UNI_APP_REMOVED" "$DEDICATED_APP_NAME"
fi

echo "ℹ️  $L_UNI_ICON_HINT"
echo "$L_UNI_ICON_HINT2"
echo "➡️  $L_UNI_RESTART"
