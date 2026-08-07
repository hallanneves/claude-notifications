# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.1] — 2026-08-07

### Fixed
- `repeat.sh stop` used `kill … && echo … || true`, where the `|| true` also covers a failing
  `echo` rather than only a failing `kill` (SC2015). Rewritten as a plain `if`.

### Changed
- CI pins shellcheck to v0.11.0. The runner image's own version differs from a typical local
  install, which is how the above slipped through a green local lint.

## [1.2.0] — 2026-08-07

### Added
- Update awareness. The `Stop` hook checks once a day (rate-limited, detached, never
  delaying a turn) whether the repository carries a version tag newer than the installed
  `VERSION`, via `git ls-remote` — no clone, no auth, no API. When it does, a clickable
  banner arrives; it stays quiet when you are already current.
- Clicking that banner opens a dialog with **Instalar / Ver no GitHub / Cancelar (Esc)**
  rather than installing straight away. This is open source running an installer on your
  machine: reading the diff first should be one click. `update.sh --yes` skips the dialog.
- `update.sh` fast-forwards the clone the skill was installed from and reinstalls, or
  shallow-clones the canonical repo when that working copy is gone. A clone with local
  commits or uncommitted work fails the fast-forward and is reported instead of rewritten.
- `NOTIFY_UPDATE_CHECK`, `NOTIFY_UPDATE_INTERVAL` and `NOTIFY_UPDATE_REPO` (point the last
  one at a fork to track it), plus a `VERSION` file installed alongside the skill.
- `notify.sh` honors `NOTIFY_EXECUTE`, turning a banner into an action: clicking it runs a
  command instead of focusing an app.

### Changed
- `approval-dialog.js` generalized into `dialog.js`, driven by a button spec
  (`"Label:key:token|…"`) so the approval and update dialogs share one NSAlert
  implementation. The timeout watchdog moved into `run_dialog` in `notify-lib.sh` with it.

## [1.1.0] — 2026-08-07

### Added
- The approval dialog is now a native `NSAlert` (`skill/approval-dialog.js`) with four
  actions, each carrying a keyboard shortcut on an underlined letter: **A**provar,
  **N**egar, abrir no **e**ditor, and a Fechar button bound to **Esc** that closes without
  deciding. AppleScript's `display dialog` could not do this — it caps at three buttons and
  supports neither per-button key equivalents nor underlined mnemonics.
- The dialog carries the Claude icon; previously it borrowed osascript's generic document
  icon badged with a caution triangle.
- `NOTIFY_DIALOG_TIMEOUT` (default 50s) configures how long the dialog waits.

### Changed
- Return is no longer bound to any button: approving takes a deliberate click or the `A`
  key, so a stray Enter can never approve a command.
- The dialog timeout moved from the JavaScript into the shell. A scheduled `NSTimer` never
  fires during `runModal` (the modal run loop uses `NSModalPanelRunLoopMode`, while the
  timer joins the default mode), so the old `giving up after` behavior was silently lost.

### Fixed
- The decision reached Claude Code only after the full timeout elapsed, even when the user
  answered in seconds: the timeout watchdog inherited the hook's stdout and held the
  caller's command substitution open. It now runs with stdout redirected.
- A token flushed by AppKit while the dialog process is torn down can no longer be read as a
  decision — once the watchdog fires, the answer is discarded and the hook falls back to the
  normal interactive prompt.

## [1.0.0] — 2026-08-07

First tagged release. Everything that existed before this tag — the `/notify` skill, the
three hooks (`Notification`, `Stop`, `PermissionRequest` with the Approve/Deny dialog), the
dedicated notifier app and the icon tooling — plus:

### Added
- `uninstall.sh`: removes the skill, the dedicated app and **only** the skill's hook entries
  from `~/.claude/settings.json`, preserving hooks from other tools (with a timestamped
  backup).
- bats test suite (35 tests) covering `notify.sh` presets and escaping, `repeat.sh` interval
  validation and PID-safety, the three hook adapters (foreground gate, dialog decisions,
  `notification_type` routing) and install/uninstall round-trips — all against a throwaway
  `HOME` with stubbed `terminal-notifier`/`osascript`/`lsappinfo`.
- GitHub Actions CI: shellcheck (Ubuntu) + bats (macOS).
- `README.en.md` (English version of the README).
- `assets/claude-logo.svg`: vector source of the icon.

### Changed
- `install.sh` is now idempotent and merges hooks **per event**: free events are added,
  events already pointing at the skill are recognized and skipped, and only events holding
  foreign hooks ask for a manual merge. Backups are timestamped
  (`settings.json.bak.<date>`) instead of overwriting a single `.bak`.
- `install-notifier-app.sh` only launches the app (and fires the authorization test
  notification) when the bundle was just created — updates no longer re-open it.
- `notify-hook.sh` routes on Claude Code's machine-readable `notification_type` field
  (permission_prompt, idle_prompt, agent_completed, …) instead of matching English substrings
  of the message; the substring match remains as a fallback for older Claude Code versions.
- `bundle-lib.sh` grew into `skill/notify-lib.sh`: single home for the dedicated-app paths,
  the click-target default and the frontmost-app gate that `stop-hook.sh` and
  `approval-hook.sh` previously duplicated. `notify.sh` no longer hardcodes the bundle path.
- `assets/claude-logo.png` regenerated at 1024×1024 from the vector source (was 266×266,
  upscaled ~4× into the icns — blurry on Retina).
- `notify.sh` warns on stderr when the requested sound does not exist (the banner would
  otherwise ship silently mute).
