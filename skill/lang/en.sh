#!/bin/bash
# English strings. Sourced by load_lang(); see pt.sh for the other catalogue.
# Every L_* here must exist in every other catalogue, with the same printf
# placeholders in the same order.
# shellcheck disable=SC2034  # consumed by the sourcing scripts

# notify.sh — the four presets
L_TITLE_APPROVAL="Approval needed"
L_TITLE_DONE="Work finished"
L_TITLE_FAIL="Something failed"
L_TITLE_INFO="Claude Code"
L_WARN_SOUND="warning: sound '%s' does not exist (see: ls /System/Library/Sounds) — the banner will be silent\n"

# notify-hook.sh
L_NEEDS_YOU="Claude Code needs you"
L_WAITING_TITLE="Claude is waiting for you"

# stop-hook.sh
L_STOP_DONE="Finished — take a look"
L_STOP_DONE_IN="Finished in %s — take a look"
L_STOP_SUBTITLE="project %s"

# approval-hook.sh
L_TOOL_FALLBACK="a tool"
L_USER_FALLBACK="the user"
L_NO_DETAILS="no details"
L_TRUNCATED="[TRUNCATED — use Open in editor to see the whole command]"
L_APPROVAL_PROMPT="Claude wants to use: %s"
L_APPROVAL_TITLE="Claude Code — approval"
L_APPROVAL_BUTTONS="Approve:a:approve|Deny:d:deny|Open in editor:e:editor|Close (Esc):esc:ignore"
L_DENY_MESSAGE="Denied by %s from the notification dialog"

# repeat.sh
L_REMINDER_TITLE="Reminder"
L_REP_USAGE="usage: repeat.sh SECONDS MESSAGE [TITLE] | stop | list"
L_REP_BAD_INTERVAL="invalid interval: '%s' (use whole seconds, >= 5)\n"
L_REP_MIN_INTERVAL="minimum interval is 5s (got %ss)\n"
L_REP_STOPPED="stopped reminder pid %s\n"
L_REP_NONE="no active reminders"
L_REP_STARTED="reminder started: pid %s, every %ss — stop with: repeat.sh stop\n"

# check-update.sh
L_UPD_UNREACHABLE="could not reach %s (offline? private repo?)\n"
L_UPD_NO_TAGS="no version tags in %s\n"
L_UPD_CURRENT="already up to date (local %s, remote %s)\n"
L_UPD_AVAILABLE="update available: %s -> %s\n"
L_UPD_BANNER_TITLE="Update available"
L_UPD_BANNER_MSG="Click to update from %s to %s"
L_UPD_BANNER_SUB="claude-notifications %s"

# update.sh
L_UPD_NO_GIT="git not found — cannot update"
L_UPD_DIALOG_TITLE="claude-notifications update"
L_UPD_DIALOG_BODY="You are on version %s. Install the latest from %s? Read what changed first if you prefer."
L_UPD_DIALOG_BUTTONS="Install:i:install|View on GitHub:g:github|Cancel (Esc):esc:cancel"
L_UPD_OPENED="opened %s — run again when you want to install\n"
L_UPD_CANCELLED="update cancelled"
L_UPD_PULL_FAIL="could not update the clone at %s (local commits or uncommitted changes?)"
L_UPD_CLONE_FAIL="could not clone %s"
L_UPD_INSTALL_FAIL="the installer failed — see %s"
L_UPD_DETAILS="details in %s"
L_UPD_SAME="Already on version %s"
L_UPD_DONE="Updated from %s to %s"
L_UPD_RESTART="%s — restart Claude Code to reload the hooks"

# install.sh / uninstall.sh
L_INS_NEED_MACOS="This skill uses native macOS notifications (osascript) — macOS required."
L_INS_NEED_JQ="jq not found (ships with macOS 15+; otherwise: brew install jq)"
L_INS_SKILL_OK="skill installed at %s\n"
L_INS_CONF_HINT="   (optional config: copy %s to notify.conf and edit)\n"
L_INS_HOOK_ADDED="hook %s added to %s\n"
L_INS_HOOK_PRESENT="hook %s already configured — nothing to do\n"
L_INS_HOOK_MANUAL="You already have your own hooks in:%s — I will not overwrite them.\n"
L_INS_HOOK_MANUAL2="    Merge those events by hand using the contents of hooks.json."
L_INS_BACKUP="   (settings.json backup at %s)\n"
L_INS_APP_FAIL="could not create the notifier app (run ./install-notifier-app.sh later)"
L_INS_TN_HINT="Recommended: brew install terminal-notifier && ./install-notifier-app.sh"
L_INS_TN_HINT2="   (without it the fallback is osascript: the banner is posted as Script Editor)"
L_INS_TEST="Test it now:  %s/notify.sh --done \"Install finished\"\n"
L_INS_RESTART="Restart Claude Code (or open /hooks) to load the hooks."
L_INS_NO_BANNER="If no banner shows: System Settings → Notifications → allow the app"
L_INS_NO_BANNER2="   (\"Claude Code\", or \"Script Editor\" when on the fallback)."
L_UNI_HOOKS_REMOVED="hooks removed from %s (backup: %s)\n"
L_UNI_NO_HOOKS="no skill hooks in %s — nothing to remove\n"
L_UNI_SKILL_REMOVED="skill removed from ~/.claude/skills/notify"
L_UNI_APP_REMOVED="app '%s' removed from ~/Applications\n"
L_UNI_ICON_HINT="If you had applied the icon to Homebrew's shared terminal-notifier:"
L_UNI_ICON_HINT2="    brew reinstall terminal-notifier   # restores the original icon"
L_UNI_RESTART="Restart Claude Code to unload the hooks."

# install-notifier-app.sh / set-claude-icon.sh
L_APP_NO_TN="terminal-notifier not found (brew install terminal-notifier)"
L_APP_EXISTS="%s already exists — keeping it (use --force to recreate).\n"
L_APP_EXISTS2="   Recreating resets the authorization: macOS asks again."
L_APP_CREATED="bundle created at %s\n"
L_APP_ICON_FAIL="could not apply the icon (run ./set-claude-icon.sh later)"
L_APP_AUTHORIZE="Authorize notifications to receive Claude Code alerts"
L_APP_ALLOW="macOS should show 'Notifications from \"Claude Code\"' — click Allow."
L_APP_ALLOW2="   If it does not: System Settings → Notifications → Claude Code → turn on"
L_APP_ALLOW3="   'Allow notifications' and set the style to Banners or Alerts."
L_ICON_APPLIED="Claude icon applied to %s\n"
L_ICON_SHARED="   This is the shared terminal-notifier: re-run after a 'brew upgrade'."
L_ICON_SHARED2="   To confine the icon to Claude's notifications: ./install-notifier-app.sh"
