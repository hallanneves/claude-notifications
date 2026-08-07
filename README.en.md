# claude-notifications

[![CI](https://github.com/hallanneves/claude-notifications/actions/workflows/ci.yml/badge.svg)](https://github.com/hallanneves/claude-notifications/actions/workflows/ci.yml)

*Versão em português: [README.md](README.md)*

Native macOS notifications (Slack-style) for **Claude Code**: a `/notify` skill + three hooks
that alert you with a **banner carrying the Claude icon and a distinct sound per event type** —
including a **native dialog with Approve/Deny buttons** when Claude needs permission and you
are away from the editor.

> Banner titles and dialog strings ship in Brazilian Portuguese (the author's setup). They are
> plain strings in `skill/notify.sh` and the hook scripts — easy to translate.

## What you get

| Event | Title | Sound | How |
|---|---|---|---|
| Claude needs approval | Aprovação necessária | Submarine (sonar) | `Notification` hook + `PermissionRequest` dialog |
| Notification you asked for | Claude Code | Glass (ding) | `/notify` skill |
| Work finished | Trabalho concluído | Hero (fanfare) | `Stop` hook + `/notify` on jobs |
| Something failed | Algo falhou | Basso (low thud) | `/notify` on jobs |

No emojis in messages: visual identity comes from the **Claude icon** on the banner
(see `set-claude-icon.sh`), semantics come from sound + title.

Smart behaviors:

- **Approval dialog**: when Claude Code is about to ask for permission and your
  editor/terminal is **not** frontmost (VSCode, Cursor, Zed, Windsurf, iTerm2, Warp,
  Ghostty…), a native dialog pops to the front carrying the Claude icon and four actions,
  each with a **keyboard shortcut on the underlined letter**:

  | Button | Shortcut | Effect |
  |---|---|---|
  | **A**provar (approve) | `A` | returns `allow` to Claude Code |
  | **N**egar (deny) | `N` | returns `deny` |
  | Abrir no **e**ditor (open in editor) | `E` | focuses the editor and lets you decide there |
  | Fechar (close) | `Esc` | closes and ignores, deciding nothing |

  Close/Esc, timeout (50s, tunable via `NOTIFY_DIALOG_TIMEOUT`), errors, or "open in editor"
  fall back to the normal terminal prompt — fail-safe. **Return does nothing**: approving
  takes a click or the `A` key, never a stray keystroke. Long commands are truncated **with an
  explicit warning** (never silently — use "open in editor" to see everything), and
  interaction tools (Claude's own questions) never trigger the dialog.
- **"Work done" without spam**: the end-of-turn banner is suppressed while your
  editor/terminal is frontmost (you are already looking at the result). Switched to Slack or
  the browser? It fires.
- **Useful click**: clicking any notification focuses VSCode (configurable via
  `NOTIFY_ACTIVATE=<bundle-id>`).
- **Periodic reminders**: `repeat.sh` runs detached and survives the end of the session.
- **New-version notice**: once a day, the end of a turn checks whether the repo carries a
  newer tag. If it does, a **clickable** banner arrives and opens a dialog offering
  **I̲nstall / View on G̲itHub / Cancel (Esc)** — a click never installs anything on its own:
  this is open source and you are entitled to read what you are about to run. Silent when
  already current, and switched off with `NOTIFY_UPDATE_CHECK=0`.

## Install

Requirements: macOS, [Claude Code](https://claude.com/claude-code), `jq` (bundled with
macOS 15+).

```bash
git clone git@github.com:hallanneves/claude-notifications.git
cd claude-notifications
brew install terminal-notifier   # recommended (icon + useful click)
./install.sh
```

The installer:

1. Copies the skill to `~/.claude/skills/notify/` (applies to **all** projects).
2. Adds the `Notification`, `Stop` and `PermissionRequest` hooks to `~/.claude/settings.json`,
   **per event**: free events are added, events already pointing at the skill are recognized
   and left alone (re-running the installer is safe — that is how you update), and events
   holding hooks **from other tools** are never overwritten — it asks for a manual merge with
   [`hooks.json`](hooks.json) for those only. A timestamped backup
   (`settings.json.bak.<date>`) is taken before any change.
3. If terminal-notifier is installed, creates the **"Claude Code"** app in `~/Applications`
   with the Claude icon (via `install-notifier-app.sh`) and opens it once so macOS shows the
   notification-permission prompt (creation only — updates never re-open the app).

Then:

1. **Restart Claude Code** (or open `/hooks`) to load the hooks.
2. Click **Allow** on the "Notifications from *Claude Code*" prompt.
3. Fire a test: `~/.claude/skills/notify/notify.sh --done "Install finished"`.
   If no banner shows: **System Settings → Notifications → Claude Code**, enable
   "Allow notifications" and set the style to **Banners** or **Alerts**.

> Without terminal-notifier the fallback is `osascript`: it works, but the banner is posted
> as Script Editor and clicking it opens an empty Script Editor window (macOS quirk for CLI
> notifications).

### The "Claude Code" app — why it exists

Two reasons, and the first decides whether you get notifications **at all**:

**1. Permission.** Running straight from the Homebrew keg, macOS (confirmed on 26.x) never
registers terminal-notifier as a notification-capable app: it never shows the permission
prompt, accepts every notification — they show up in `terminal-notifier -list ALL` — and
**silently drops the banner**. Every command exits 0, no error anywhere, nothing on screen. A
bundle with its own identity under `~/Applications`, **launched once**, gets the prompt
normally.

**2. Icon.** macOS shows the icon of the *posting* app and won't let you customize it per
notification (`-appIcon` is accepted and ignored; `-sender` **hangs the process** and never
delivers — use neither). Swapping the shared `terminal-notifier.app` icon works, but brands
**every** other terminal-notifier caller on the machine with the Claude logo — and
`brew upgrade` reverts it. With the dedicated app, the logo stays contained.

As a bonus, it gets its own entry in Settings → Notifications ("Claude Code"), with
independent sound, style and Focus.

```bash
./install-notifier-app.sh            # create (preserves an existing one and its authorization)
./install-notifier-app.sh --force    # recreate from scratch — macOS asks for permission again
./set-claude-icon.sh                 # just re-apply the icon
```

`set-claude-icon.sh` targets the dedicated app when it exists; without it, it falls back to
Homebrew's terminal-notifier.app — in which case `brew upgrade` restores the stock icon and
the script must be re-run.

## Usage in Claude Code

- `/notify deploy finished` — immediate banner.
- *"run the suite and tell me when it's done"* — Claude runs the job in the background and
  notifies success or failure **based on the real outcome** (the skill forbids notifying
  success without checking the exit code).
- *"remind me to stretch every 30 minutes"* — detached periodic reminder.
- `/notify list` / `/notify stop` — manage active reminders.

Straight from the shell (outside Claude):

```bash
~/.claude/skills/notify/notify.sh --done "build ok"
~/.claude/skills/notify/notify.sh --fail "build broke"
~/.claude/skills/notify/notify.sh "message" "Title" "subtitle" "Ping"
~/.claude/skills/notify/repeat.sh 1800 "stretch!"     # every 30 min
~/.claude/skills/notify/repeat.sh stop
~/.claude/skills/notify/check-update.sh --force       # any new version?
~/.claude/skills/notify/update.sh                     # update now
```

### Updating

The `Stop` hook runs `check-update.sh` detached, at most once a day (the query is a
`git ls-remote` over tags — no clone, no auth, no API). When the remote carries a tag newer
than the installed `VERSION`, a clickable banner arrives.

The click **installs nothing**: it opens a dialog with three ways out — **I̲nstall**, **View
on G̲itHub** (opens the releases page and exits without touching anything) and **Cancel**,
bound to `Esc`. That detour is deliberate: this is free software about to run an installer on
your machine, so reading the diff first should be one click, not an excavation.
`update.sh --yes` skips the dialog for anyone scripting it.

On install it runs `git pull --ff-only` in the clone it was installed from (recorded at
install time) and reinstalls; if that clone is gone, it shallow-clones the canonical repo into
a temporary directory. Nothing is forced: a clone with local commits or uncommitted work fails
the fast-forward and you get a failure banner instead of a rewritten history. After updating,
**restart Claude Code** so the hooks reload.

## How it works

```
claude-notifications/
├── install.sh              # installs skill + hooks (+ app when possible); idempotent, with backup
├── uninstall.sh            # removes skill, app and ONLY the skill's hooks (others preserved)
├── install-notifier-app.sh # creates the "Claude Code" app in ~/Applications (permission + isolated icon)
├── set-claude-icon.sh      # applies the Claude icon to the dedicated app (or terminal-notifier)
├── hooks.json              # hook snippet for manual merges into settings.json
├── VERSION                 # installed version, compared against the remote's tags
├── assets/
│   ├── claude-logo.png     # 1024×1024 icon (generated from the SVG next to it)
│   └── claude-logo.svg     # vector source of the icon
├── skill/
│   ├── SKILL.md            # instructions Claude Code loads (/notify)
│   ├── notify-lib.sh       # shared constants + helpers (bundle paths, foreground gate)
│   ├── notify.sh           # native banner (terminal-notifier or osascript)
│   ├── repeat.sh           # detached periodic reminders (start/list/stop)
│   ├── notify.conf.example # optional config (click target, suppressing apps)
│   ├── notify-hook.sh      # Notification hook → routes by notification_type
│   ├── stop-hook.sh        # Stop hook → "done" banner (suppressed with editor focused)
│   ├── approval-hook.sh    # PermissionRequest hook → Approve/Deny dialog
│   ├── dialog.js           # generic NSAlert (underlined shortcuts + Claude icon)
│   ├── check-update.sh     # is there a newer version? (rate-limited, clickable banner)
│   └── update.sh           # the Install / View on GitHub / Cancel dialog, then reinstall
└── tests/                  # bats suite (runs in CI on macOS + shellcheck)
```

Security notes of the design:

- `repeat.sh stop` only kills processes provably its own (checks a marker in `ps` before
  `kill` — a recycled post-reboot PID is never a target) and rejects invalid intervals or
  anything under 5s (a broken `sleep` would turn the loop into a notification firehose).
- `install.sh` takes a timestamped backup (`settings.json.bak.<date>`) before touching your
  hooks and never overwrites hooks from other tools; `uninstall.sh` removes **only** hook
  entries pointing at the skill, leaving everything else intact.
- The `Notification` hook routes on Claude Code's `notification_type` field (permission,
  waiting, agent finished…), with a keyword fallback for older versions.

The foreground gate uses `lsappinfo` (no extra permissions). The decision is returned as
`hookSpecificOutput.decision.behavior: "allow" | "deny"`; any unexpected path exits 0 with no
output, which makes Claude Code show the normal interactive prompt.

The dialog is an **NSAlert** (JXA), not AppleScript's `display dialog` — the latter caps at
three buttons (we need four) and supports neither per-button shortcuts nor underlined
mnemonics. Three details that only surface once you try:

- The timeout lives in the **shell**, not in JavaScript: a scheduled `NSTimer` never fires
  during `runModal`, because the modal runs in `NSModalPanelRunLoopMode` while the timer
  joins the default mode.
- The timeout watchdog runs with stdout redirected. Without that it holds the caller's pipe
  open, and the decision only reaches Claude Code once the whole timeout elapses — even if
  you answered in two seconds.
- Underlined titles are applied **after** `alert.layout`: NSAlert rebuilds its buttons'
  titles while laying out and would drop an `attributedTitle` set any earlier.

> **Note**: the response format used (`hookSpecificOutput.decision.behavior`) is the currently
> documented `PermissionRequest` format, and the allow and deny paths were also tested live in
> this setup.

## Customization

Create `~/.claude/skills/notify/notify.conf` (a `notify.conf.example` is installed next to it):

```bash
# App focused when clicking a notification (default: VSCode).
# Find your editor's bundle id: osascript -e 'id of app "Cursor"'
NOTIFY_ACTIVATE="com.todesktop.230313mzl4w4u92"

# Extra apps that suppress the "done" banner and the dialog while frontmost
NOTIFY_FRONT_APPS="MyEditor,OtherTerminal"

# Binary used to post. Defaults to the dedicated app when present, else the
# terminal-notifier on PATH. Only set to point at another bundle.
NOTIFY_TN="$HOME/Applications/Claude Code Notifier.app/Contents/MacOS/terminal-notifier"

# Seconds the approval dialog waits before giving up (default: 50).
NOTIFY_DIALOG_TIMEOUT=50

# Update check (clickable banner). 0 turns it off.
NOTIFY_UPDATE_CHECK=0
# Minimum seconds between checks (default: 86400 = one day).
NOTIFY_UPDATE_INTERVAL=86400
# Repository consulted — point it at a fork to track that instead.
NOTIFY_UPDATE_REPO="https://github.com/hallanneves/claude-notifications.git"
```

Other knobs:

- **Sounds**: any name from `ls /System/Library/Sounds` (Glass, Hero, Basso, Submarine,
  Ping…), passed as `notify.sh`'s 4th argument — an unknown name prints a warning to stderr
  (the banner would otherwise be silently mute).
- **Icon**: replace `assets/claude-logo.png` (square, 1024×1024, with alpha) and re-run
  `set-claude-icon.sh`. The PNG is generated from `assets/claude-logo.svg` with
  `resvg --width 1024 --height 1024 assets/claude-logo.svg assets/claude-logo.png`.
- **Reminders**: `repeat.sh`'s minimum interval is 5s (spam-loop protection).

## Uninstall

```bash
./uninstall.sh
```

Removes the skill, the dedicated app and the skill's hook entries in
`~/.claude/settings.json` (hooks from other tools are left intact; a timestamped backup is
taken first). If you had applied the icon to Homebrew's shared terminal-notifier:
`brew reinstall terminal-notifier` restores the original.

## Development

```bash
brew install shellcheck bats-core
shellcheck -x -P SCRIPTDIR -S style install.sh uninstall.sh install-notifier-app.sh set-claude-icon.sh skill/*.sh
bats tests
```

The same pair runs in CI (GitHub Actions): shellcheck on Ubuntu, bats on a macOS runner. The
tests use a throwaway `HOME` and stubs for `terminal-notifier`/`osascript`/`lsappinfo` — no
test fires a real notification or touches your `settings.json`.

## License

Code under [MIT](LICENSE). The logo (`assets/claude-logo.png`/`.svg`) is an Anthropic
trademark, used only to identify Claude Code notifications — not covered by the MIT license.
