# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.9.1] — 2026-10-20

### Fixed
- **The approval panel ignored every click and key.** Its event loop asked Cocoa for
  `NSEventMaskAny`, which is `NSUIntegerMax`: JXA rounds that to 2^63, a mask no event
  matches, so the buttons, the close box and the shortcuts were all dead and the dialog only
  ever ended by timing out (back to the terminal's own prompt). The 1.9.0 check pressed the
  button with `performClick`, which skips the event queue. `dialog.js --simulate` now drives
  the real panel, fully transparent, with clicks and keys through that same queue, and the
  suite covers every button and shortcut.
- **N, I and Esc did nothing after clicking into the panel**: the command box became first
  responder and swallowed the letter. Shortcuts are matched in the event loop now, and a click
  anywhere on the panel hands it the keyboard. Before that click, keys still go to your app.

## [1.9.0] — 2026-10-20

The exact VSCode tab, and an approval dialog that leaves your keyboard alone. Closes #3.

### Added
- **VSCode bridge extension** (`vscode-bridge/`, installed by `install.sh` into `code` and
  `cursor` when present, only when its version changed; `NOTIFY_BRIDGE=0` skips it). A click,
  or "Go to session", now reveals the session's **Claude tab** — or the **integrated
  terminal** running Claude — in the window that owns the session. Each window publishes a
  small registry and listens on its own Unix socket; the click picks the window by process
  ancestry (the session descends from that window's extension host or one of its terminals'
  shells) and asks only it. A `vscode://` URL could not do this: it goes to whichever window
  was active last, where the Claude extension would open a second panel resuming a session
  still running elsewhere. Packaged as a `.vsix` with `zip`, so installing needs neither node
  nor vsce.
- **"Always approve: <rule>"** in the approval dialog, when Claude Code offers
  `permission_suggestions`: the suggestion is returned verbatim as `updatedPermissions`,
  exactly the terminal's "don't ask again".
- **One dialog at a time**: parallel sessions queue (up to `NOTIFY_DIALOG_QUEUE_SECS`, 30s)
  instead of stacking modal windows; a lock left by a dead process is taken over.
- **The dialog closes itself** when you look at the session again; its own prompt takes over.

### Changed
- **The approval dialog no longer takes the keyboard.** It is a floating, non-activating
  panel: the app you were typing in keeps the keyboard, and you decide with a click. Letter
  shortcuts work only after you click into the panel. Measured live before shipping: the
  frontmost app does not change, osascript never becomes active, the panel never becomes key.
  The update dialog uses the same panel.

## [1.8.0] — 2026-10-15

Per-session focus, starting with herdr, and a banner worth reading.

### Added
- **herdr**: a click focuses the session's **exact pane** — looked up by Claude session id,
  so a pane that moved is still found — and brings forward the Terminal or iTerm2 tab running
  the herdr client. "Go to session" in the approval dialog does the same.
- **`doctor.sh`** (`--test` too): where the session runs, whether you count as looking and
  why, where a click would land, the notifier's health, denied Automation permissions, and
  herdr's duplicate sound. `--test` posts a banner and reports what the click actually did.
- **`UserPromptSubmit` hook** (`prompt-hook.sh`, async): answering a session removes its
  notifications from Notification Center and starts the turn clock.
- **One notification per session**: all of a session's banners share a group, so a new one
  replaces the last instead of piling up.
- The "done" banner says what happened: `<project> · done`, the branch (and the herdr
  session title) as subtitle, and the first line of Claude's answer (`last_assistant_message`)
  as body. `NOTIFY_PREVIEW=off` keeps the answer off it.
- `NOTIFY_MIN_TURN_SECS` (default 30): quick turns make no noise.
- Per-event sounds (`NOTIFY_SOUND_TURN`, `_APPROVAL`, `_DONE`, `_FAIL`, `_INFO`), and `none`
  to silence one — an empty sound used to fall back to the preset.

### Fixed
- **"Looking at it" meant "any editor or terminal in front"**: with VSCode in front, a session
  running in Terminal or herdr never notified. The app showing **that** session must be in
  front now and, under herdr, its pane on screen.
- The session's origin comes from the **process tree**, not from environment variables:
  herdr and tmux leak the variables of whatever terminal started their server, and a
  `code .` run from a pane carried herdr's variables into VSCode.
- `idle_prompt` no longer repeats a "done" banner the same session got minutes before, and
  stays quiet while you look at the session.
- The approval banner reads `<project> · approval`, with the tool as subtitle.

### Changed
- End-of-turn banners use Glass; Hero is kept for jobs you asked to hear about.
- Runtime state moved out of the skill directory (which every install replaces) to
  `~/Library/Application Support/claude-notifications` (`NOTIFY_STATE_DIR`), migrated once
  on the first run; an active mute or a running reminder survives it. `uninstall.sh` removes it.

## [1.7.0] — 2026-10-14

Critical fixes from a review of how the tool behaves outside "one VSCode window". No new
architecture yet: that comes with per-session focus (herdr panes, VSCode tabs) next.

### Security
- **The approval dialog showed a different command from the one that would run.** It replaced
  `"` with `'` and `\` with `/`, and cut at 350 characters. It now shows the command byte for
  byte, whole, in a scrolling monospaced box, with control, zero-width and bidi characters
  rendered as a visible `⟨U+XXXX⟩` so they can neither hide nor reorder text.
- **A stray keystroke could approve a command.** The dialog takes keyboard focus from the app
  you are typing in, and `a` approved. Approve now has no shortcut at all: only a click. The
  other shortcuts arm 0.7s after the dialog appears.
- `focus.sh` no longer `eval`s a command built from the session's folder (a `'` in the path
  broke it, and could inject), and AppleScript receives values as arguments instead of having
  them spliced into its source.

### Fixed
- **A permission request could raise no notification at all**: with the editor in front, the
  approval hook skipped its banner, and the Notification hook stayed silent because the
  approval hook was installed. The Notification hook now goes quiet only when the approval
  hook actually announced that session's request.
- **"Looking at it" now also means "at the keyboard"**: the editor left in front during a
  coffee break no longer swallows the "done" banner and the approval dialog
  (`NOTIFY_AWAY_SECS`, default 60).
- **A click never opens an app the session has nothing to do with.** The default target was
  VSCode for everyone: a click on a Terminal or herdr session launched VSCode, as did a
  Terminal tab that had closed or an Automation permission that was denied. The target is now
  the app hosting the session (`NOTIFY_ACTIVATE` still overrides).
- In an editor, the click opens the **workspace root** recorded by the Claude extension
  instead of the session's folder, which created a new window whenever Claude ran in a
  subfolder or worktree.
- `ITERM_SESSION_ID` inherited inside tmux/herdr no longer points the click at an unrelated
  iTerm2 tab.
- A Claude question (`AskUserQuestion`) or a plan ready for review (`ExitPlanMode`) while you
  are away now posts a "your turn" banner; before, both were silent.
- Unknown notification types (`quota_auto_resume_*`…) post an info banner instead of the
  approval sonar. `elicitation_url_dialog` is treated as a wait, like `elicitation_dialog`.
- A generic `Electron` app in front no longer counts as an editor.

### Added
- The approval dialog names the **project and branch** asking, and its banner carries Claude's
  description of the command (never the command itself).
- A denied Automation permission posts **one** notice whose click opens System Settings →
  Privacy & Security → Automation, instead of failing silently.
- The notifier app declares `NSAppleEventsUsageDescription` (added once to existing bundles).

### Changed
- "Open in editor" is now **"Go to session"**: it was wrong for terminal users.
- Re-running the installer no longer re-signs the notifier app when its icon is unchanged:
  every ad-hoc re-sign changes the bundle's hash, and macOS may forget permissions granted
  to it.

## [1.6.0] — 2026-08-16

### Added
- Clicking a notification now returns to the **exact terminal tab** that raised it, when the
  host exposes one: iTerm2 matched by `ITERM_SESSION_ID`, Terminal.app matched by the tty.
  The identity is captured while the hook runs and baked into the click action, because none
  of it is reachable by the time someone clicks. "Open in editor" takes the same route.
- A terminal session that has since closed falls through to the project window rather than
  failing, and a host with no session identity behaves exactly as before.

### Known limits
- Running Claude Code as an **editor extension** (the VS Code integration), there is no
  terminal session to identify: no tty, no `TERM_PROGRAM`, no session id — the process tree is
  `claude` → `Code Helper (Plugin)` → `Code`. Focusing the window that holds the project
  folder is the ceiling there.
- **No editor exposes its windows or tabs to AppleScript** (VS Code answers `-1728` to a
  window query), so "which tab" is not addressable for editors at all. Raising a window by
  title through System Events would need Accessibility permission and still could not
  separate two windows on the same folder.

## [1.5.0] — 2026-08-16

Both open issues.

### Added
- **Focus mode** (#2). `mute.sh 30m` (also `45s`, `2h`, `1d`, `on`, `off`, `status`) silences
  banners, reminders and the update notice — **and the approval dialog**, which is the loudest
  interruption of the three. While muted a permission request falls back to Claude Code's
  terminal prompt, which waits quietly. macOS Focus already hides banners, but nothing in it
  holds back a modal dialog, which is why this could not be delegated to the system.
- An expired or corrupted mute stamp clears itself, so a bad file can never silence the tool
  forever.

### Changed
- **Clicking a notification lands on the right window** (#3). The hooks now pass the session's
  `cwd`, and the click runs `open -b <bundle> <folder>` instead of merely activating the app —
  which focuses the window already holding that project. With several projects open you no
  longer arrive at whichever window happened to be in front.
  Folders go only to editor bundles: handing a path to a terminal would open a new window
  rather than focus anything. `NOTIFY_ACTIVATE_PATH=always|never` overrides the guess.
- "Open in editor" in the approval dialog follows the same route, so it opens the project the
  permission came from.

## [1.4.0] — 2026-08-07

### Fixed
- One permission request produced **two banners and two sonar sounds**: it raises both
  `Notification` (with `notification_type: permission_prompt`) and `PermissionRequest`, and
  both hooks were posting. The Notification hook now stays silent on that event when the
  PermissionRequest hook is wired — checked in `settings.json`, so a setup with only the
  Notification hook keeps its banner.
- `update.sh` advertised a tag and installed a branch: it compared against the newest tag but
  then ran `git pull` on the default branch, delivering whatever unreleased commits happened
  to be on it. It now clones the exact tag it advertised (`--branch <tag>`) into a throwaway
  directory. Your own working copy is never touched, which also retires the whole
  "fast-forward failed because you have local commits" failure mode.

### Added
- The approval **banner no longer carries the command** by default. macOS previews
  notifications on the lock screen, so a `Bash` call holding a token or password was readable
  on a locked machine. The banner now names the tool; the full command stays in the dialog,
  which requires an unlocked session. `NOTIFY_BANNER_DETAIL=full` restores the old banner.
- `NOTIFY_DEBUG=1` appends one line per hook call to `.debug.log`. Every error path exits 0 in
  silence by design — right for safety, unhelpful for support — and this is the way to see
  what actually happened.
- `dialog.js` is now syntax-checked in the suite with `osacompile`, which parses it without
  opening a window. The tests stub `osascript`, so nothing else ever executed that file: a
  syntax error would have passed CI and shown up only as "the approval dialog stopped
  appearing", silently, because a broken dialog lands on the fail-safe path.
- The skill's trigger description is bilingual and its body is in English. The `description`
  is what Claude Code matches a request against, and it listed Portuguese phrases only — so
  "notify me when the build finishes" was being matched against Portuguese text.

### Changed
- CI also lints `tests/helpers.bash`.
- `.update.log` and `.debug.log` are trimmed to their tail past 64 KB instead of growing
  forever.

## [1.3.0] — 2026-08-07

### Added
- The interface speaks English and Portuguese. Every user-facing string — banner titles,
  dialog buttons, hook messages, installer and uninstaller output, CLI errors — moved into
  per-language catalogues under `skill/lang/`, and the language is picked from the macOS
  locale (`AppleLocale`), overridable with `NOTIFY_LANG` in `notify.conf` or the environment.
  Anything without a catalogue falls back to English.
- Mnemonics are translated along with the labels, so the approval dialog reads
  **A**pprove / **D**eny / open in **e**ditor in English and
  **A**provar / **N**egar / abrir no **e**ditor in Portuguese — each shortcut is the initial
  of the word actually on the button.
- Two guard tests: the catalogues must define exactly the same keys, and every `$L_*`
  referenced by a script must exist in both. A missing key would otherwise render as an
  empty string with no error at all.

### Changed
- Region no longer decides the language: `en_BR` resolves to English, `pt_BR` to Portuguese.
- The deny reason is now built with `jq` instead of `printf`, so a username containing a
  quote cannot corrupt the hook's JSON response.
- `update.sh` reloads the catalogue after installing, so the closing banner speaks the
  language shipped by the new version rather than the one that started the update.

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
