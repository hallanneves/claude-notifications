# claude-notifications

[![CI](https://github.com/hallanneves/claude-notifications/actions/workflows/ci.yml/badge.svg)](https://github.com/hallanneves/claude-notifications/actions/workflows/ci.yml)

*Versão em português: [README.md](README.md)*

Native macOS notifications (Slack-style) for **Claude Code**, as a **plugin**: a `/notify`
skill + hooks that alert you with a **banner carrying the Claude icon and a distinct sound per
event type** — including a **panel with Approve/Deny** when Claude needs permission and you are
not looking — and a click that returns to the **exact session**.

> **Language**: the interface speaks **English and Portuguese**. It follows the macOS locale
> (Settings → Language & Region); force it with `NOTIFY_LANG="en"` or `"pt"` in `notify.conf`.
> Adding a language is one file in [`skills/notify/lang/`](skills/notify/lang) — copy `en.sh`, translate the
> values, name it after the language code.

## What you get

| Event | Title | Sound | How |
|---|---|---|---|
| Claude needs approval | Approval needed | Submarine (sonar) | `Notification` hook + `PermissionRequest` dialog |
| Notification you asked for | Claude Code | Glass (ding) | `/notify` skill |
| Turn finished (you are away) | `<project> · done` | Glass (ding) | `Stop` hook |
| A job you asked to hear about | Work finished | Hero (fanfare) | `/notify` on jobs |
| Something failed | Something failed | Basso (low thud) | `/notify` on jobs |

No emojis in messages: visual identity comes from the **Claude icon** on the banner
(see `set-claude-icon.sh`), semantics come from sound + title.

Smart behaviors:

- **Approval dialog**: when Claude Code is about to ask for permission and you are **not
  looking** (editor/terminal not frontmost, or nobody at the keyboard for over 60s), a panel
  floats above everything with the Claude icon, the **project and branch** asking, and the
  actions. The panel **does not take the keyboard**: you keep typing where you were, and
  decide with a click.

  | Button | Shortcut | Effect |
  |---|---|---|
  | Approve | **click only** | returns `allow` to Claude Code |
  | Always approve: `<rule>` | **click only** | approves and saves the rule Claude Code itself suggests (the terminal's "don't ask again"); shown only when there is one |
  | **D**eny | `D` | returns `deny` |
  | **G**o to session | `G` | returns to the session's tab or window and lets you decide there |
  | Close | `Esc` | closes and ignores, deciding nothing |

  Close/Esc, timeout (50s, tunable via `NOTIFY_DIALOG_TIMEOUT`), errors, or "go to session"
  fall back to the normal terminal prompt — fail-safe. **No key approves**, and the other
  buttons' shortcuts work only after you click into the panel. Went back to the session with
  the panel open? It closes on its own and the session's prompt takes over. Several sessions
  asking at once wait their turn, one panel at a time. The command shows **whole and exactly
  as it will run**, in a scrolling box; invisible characters (control, zero-width, bidi) show
  up as `⟨U+202E⟩` instead of hiding or reordering text. Claude's own questions and a plan
  ready for review never open the dialog: they become a "your turn" banner while you are away.
- **"Done" only when it matters**: the end-of-turn banner stays quiet while you are looking
  **at that session**: the app showing it in front (Terminal for a Terminal session; VSCode in
  front does not count), someone at the keyboard and, under herdr, its pane on screen.
  Switched to Slack, sitting in another pane, or left it all in front and went for coffee
  (`NOTIFY_AWAY_SECS`, default 60s)? It fires. Short turns (under 30s, `NOTIFY_MIN_TURN_SECS`)
  make no noise.
- **The banner says what happened**: the project in the title (`claude-notifications ·
  done`), the branch and, under herdr, the session's title as subtitle, and the first line of
  Claude's answer as the body. `NOTIFY_PREVIEW=off` keeps the answer off the banner.
- **One notification per session**: each notice replaces the session's previous one, and
  answering the session clears its notices from Notification Center.
- **A click returns you to where you were, never to another app**: under **herdr**, the click
  focuses the session's **exact pane** (found by session id, even after the pane moved) and
  brings forward the Terminal or iTerm2 tab herdr runs in. In a terminal, it selects the
  **exact tab** that raised the notification (iTerm2 by session id, Terminal.app by tty). In
  **VSCode** (and Cursor), with the bridge extension the installer adds, the click opens the
  session's **exact Claude tab** or the **integrated terminal** it runs in, in the window that
  owns the session. Without the bridge, it focuses the project's window by its workspace root
  (opening a subfolder would create a new window).
  A tab that is gone falls back to the app hosting the session: a Terminal or herdr session
  never opens VSCode. If macOS denies the Automation permission, you get **one** notice with a
  click to System Settings. `NOTIFY_ACTIVATE_PATH=never` restores plain app focus.
- **Mute to focus**: `mute.sh 30m` silences everything for half an hour — banners, reminders
  and **the approval dialog too**, which is the most aggressive interruption of the lot. While muted, a permission request falls back to the normal terminal prompt,
  which waits quietly. macOS Focus hides banners but does not hold back a modal dialog.
- **No secrets on the lock screen**: the approval banner names the tool Claude wants to use
  and Claude's own description of the command, never the command. The full command lives in the dialog, which needs an unlocked session — macOS previews
  notifications while the screen is locked. `NOTIFY_BANNER_DETAIL=full` restores the old
  behaviour.
- **Periodic reminders**: `repeat.sh` runs detached and survives the end of the session.
- **Updates through Claude Code's plugin system** (see [Updates](#updates)).

## Install

Requirements: macOS, [Claude Code](https://claude.com/claude-code) 2.1.275 or later and `jq`
(bundled with macOS 15+). Recommended: `brew install terminal-notifier` (the Claude icon and a
useful click).

In Claude Code:

```
/plugin install notify --marketplace hallanneves/claude-notifications
```

Or from a terminal, `claude plugin install notify --marketplace hallanneves/claude-notifications`,
or clone the repo and run `./install.sh`, which does the same and also migrates a 1.x install.

The first session after installing sets things up **in the background**, once per version,
and says so in a message:

1. If terminal-notifier is installed, it creates the **"Claude Code"** app in `~/Applications`
   with the Claude icon (`install-notifier-app.sh`) and opens it once so macOS shows the
   notification-permission prompt (creation only — updates never re-open the app).
2. If `code` (or `cursor`) is on PATH, it installs the **bridge extension**
   ([`vscode-bridge/`](vscode-bridge)), which takes a click to the right Claude tab or
   integrated terminal. `NOTIFY_BRIDGE=0` in `notify.conf` skips this step.

Then:

1. Click **Allow** on the "Notifications from *Claude Code*" prompt.
2. Test it: `/notify install finished`. If no banner shows: **System Settings → Notifications
   → Claude Code**, enable "Allow notifications" and set the style to **Banners** or
   **Alerts**. `/notify doctor` tells what is missing.

> Without terminal-notifier the fallback is `osascript`: it works, but the banner is posted
> as Script Editor and clicking it opens an empty Script Editor window (macOS quirk for CLI
> notifications).

### Updates

Claude Code adds third-party marketplaces with **auto-update off**. To turn it on: `/plugin` →
**Marketplaces** → `claude-notifications` → **Enable auto-update**. The first session reminds
you once, and `/notify doctor` shows the state. Without it, update whenever you like with
`/plugin update notify@claude-notifications`. A new version applies from the next session (or
`/reload-plugins`).

### Coming from 1.x

1.x copied the skill to `~/.claude/skills/notify` and wrote its hooks into
`~/.claude/settings.json`. Claude Code runs a plugin's hooks **next to** the ones in
`settings.json`, without deduplicating; so while 1.x is still wired the plugin stands by
(nothing fires twice) and each session asks for:

```
/notify migrate
```

It removes **only** 1.x's hooks from `settings.json` (with a timestamped backup; other tools'
hooks stay), moves `notify.conf` and the state to
`~/Library/Application Support/claude-notifications`, stops the old copy's reminders and
deletes `~/.claude/skills/notify`. Then **restart the sessions already open**: they started
with the old hooks.

2.0's `./install.sh` installs and migrates in one go, and it is what the 1.x update notice
runs: clicking **Install** lands on 2.0, already migrated.

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

From a clone of the repo:

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
- *"mute for an hour"* / *"you can notify me again"* — focus mode.
- `/notify doctor` — why it notified (or not), and where a click goes.
- `/notify migrate` — finishes the move from 1.x to the plugin.

Straight from the shell (outside Claude), from a clone of the repo:

```bash
skills/notify/notify.sh --done "build ok"
skills/notify/notify.sh --fail "build broke"
skills/notify/notify.sh "message" "Title" "subtitle" "Ping"
skills/notify/repeat.sh 1800 "stretch!"     # every 30 min
skills/notify/repeat.sh stop
skills/notify/mute.sh 30m                   # silence for 30 min
skills/notify/mute.sh off                   # unmute
skills/notify/mute.sh status                # current state
skills/notify/doctor.sh                     # why it notified (or not), and where a click goes
skills/notify/doctor.sh --test              # posts a banner; click it to see what the click did
```

## How it works

```
claude-notifications/
├── .claude-plugin/
│   ├── plugin.json         # the "notify" plugin (name, version)
│   └── marketplace.json    # the repo is its own "claude-notifications" marketplace
├── hooks/hooks.json        # SessionStart, Notification, Stop, PermissionRequest, UserPromptSubmit
├── install.sh              # installs the plugin through Claude Code's CLI and migrates 1.x
├── uninstall.sh            # removes plugin, app, bridge, state and what 1.x left behind
├── vscode-bridge/          # VSCode bridge extension: exact Claude tab and integrated terminal
├── install-notifier-app.sh # creates the "Claude Code" app in ~/Applications (permission + isolated icon)
├── set-claude-icon.sh      # applies the Claude icon to the dedicated app (or terminal-notifier)
├── VERSION                 # equals plugin.json's "version" (a test checks)
├── assets/
│   ├── claude-logo.png     # 1024×1024 icon (generated from the SVG next to it)
│   └── claude-logo.svg     # vector source of the icon
├── skills/notify/
│   ├── SKILL.md            # instructions Claude Code loads (/notify)
│   ├── lang/               # string catalogues (en.sh, pt.sh)
│   ├── notify-lib.sh       # shared constants + helpers (origin, gate, language, plugin)
│   ├── notify.sh           # native banner (terminal-notifier or osascript)
│   ├── repeat.sh           # detached periodic reminders (start/list/stop)
│   ├── mute.sh             # focus mode: silences banners and the approval dialog
│   ├── notify.conf.example # optional config (language, click target, sounds, timeouts)
│   ├── session-hook.sh     # SessionStart hook → sets the version up, asks to migrate 1.x
│   ├── setup.sh            # notifier app + bridge extension, once per version
│   ├── migrate.sh          # /notify migrate: retires a 1.x install
│   ├── notify-hook.sh      # Notification hook → routes on notification_type
│   ├── stop-hook.sh        # Stop hook → "done" banner (quiet while you watch the session)
│   ├── prompt-hook.sh      # UserPromptSubmit hook → clears the session's notices, times the turn
│   ├── doctor.sh           # diagnosis: origin, gate, click, notifier, plugin, herdr
│   ├── approval-hook.sh    # PermissionRequest hook → Approve/Deny dialog
│   ├── focus.sh            # the click: herdr pane, terminal tab, Claude tab in VSCode
│   └── dialog.js           # floating panel that leaves the keyboard alone
└── tests/                  # bats suite (runs in CI on macOS + shellcheck)
```

Security notes of the design:

- `repeat.sh stop` only kills processes provably its own (checks a marker in `ps` before
  `kill` — a recycled post-reboot PID is never a target) and rejects invalid intervals or
  anything under 5s (a broken `sleep` would turn the loop into a notification firehose).
- `/notify migrate` and `uninstall.sh` take a timestamped backup (`settings.json.bak.<date>`)
  before touching your hooks and remove **only** the entries pointing at the 1.x copy, leaving
  everything else intact. Migrating requires the plugin installed: without it you would be
  left with no notifications at all.
- The `Notification` hook routes on Claude Code's `notification_type` field (permission,
  waiting, agent finished…), with a keyword fallback for older versions. A permission request
  raises both events: whichever announces it (banner + dialog) leaves a per-session stamp and
  the other keeps quiet, so it is one banner and one sonar per request. When the dialog did not
  appear (you were looking, then walked away), `permission_prompt` is the request's only voice
  and speaks. Unknown types become an informational banner, never the approval sonar.

The foreground gate uses `lsappinfo` (no extra permissions). The decision is returned as
`hookSpecificOutput.decision.behavior: "allow" | "deny"`; any unexpected path exits 0 with no
output, which makes Claude Code show the normal interactive prompt.

The dialog is a **non-activating `NSPanel`** (JXA), not an NSAlert nor AppleScript's
`display dialog`. An NSAlert activates its app and becomes the key window, so whatever you
were typing in Slack landed in it and a stray letter pressed a button; `display dialog` caps
at three buttons. Details that only surface once you try:

- The panel is shown with `orderFrontRegardless` and **no `runModal`**: a modal session makes
  the panel key. Events are pumped by hand, and the panel takes the keyboard only when you
  click it. The loop's mask is `-1`, not `NSEventMaskAny`: that one is `NSUIntegerMax`, which
  JXA rounds to 2^63, and no event matches it (in 1.9.0 the panel ignored every click). The
  shortcuts are read in the loop itself, before the command box swallows the letter.
- The timeout lives in the **shell**, which kills the process when it expires; the same
  watcher closes the panel when you look at the session again.
- The timeout watchdog runs with stdout redirected. Without that it holds the caller's pipe
  open, and the decision only reaches Claude Code once the whole timeout elapses — even if
  you answered in two seconds.
- "Always approve" returns, **verbatim**, a suggestion that came in `permission_suggestions`:
  the Claude extension itself only accepts `updatedPermissions` matching an offered
  suggestion.

> **Note**: the response format used (`hookSpecificOutput.decision.behavior`) is the currently
> documented `PermissionRequest` format, and the allow and deny paths were also tested live in
> this setup.

## Customization

Create `~/Library/Application Support/claude-notifications/notify.conf` (outside the plugin,
so updates leave it alone; template in
[`skills/notify/notify.conf.example`](skills/notify/notify.conf.example)):

```bash
# Interface language: "en" or "pt". Without this, it follows the macOS locale.
NOTIFY_LANG="en"

# App focused when clicking a notification. Default: the app hosting the
# session (Terminal, iTerm2, VSCode, Cursor…), detected on its own.
# Find an app's bundle id: osascript -e 'id of app "Cursor"'
NOTIFY_ACTIVATE="com.todesktop.230313mzl4w4u92"

# Seconds without keyboard or mouse input that count as away (default: 60).
NOTIFY_AWAY_SECS=60

# Turns shorter than this post no "done" banner (default: 30; 0 = always).
NOTIFY_MIN_TURN_SECS=30

# "off" keeps the first line of Claude's answer off the banner (lock screen).
NOTIFY_PREVIEW=on

# Each event's sound. "none" silences it. End of turn: Glass. Presets:
# Submarine, Hero, Basso, Glass.
NOTIFY_SOUND_TURN=Glass
NOTIFY_SOUND_DONE=Hero

# Extra apps that suppress the "done" banner and the dialog while frontmost
NOTIFY_FRONT_APPS="MyEditor,OtherTerminal"

# Binary used to post. Defaults to the dedicated app when present, else the
# terminal-notifier on PATH. Only set to point at another bundle.
NOTIFY_TN="$HOME/Applications/Claude Code Notifier.app/Contents/MacOS/terminal-notifier"

# Seconds the approval dialog waits before giving up (default: 50).
NOTIFY_DIALOG_TIMEOUT=50

# What the approval banner shows: "tool" (default) or "full" (includes the command).
NOTIFY_BANNER_DETAIL=tool

# One line per hook call in .debug.log — hooks fail silently by design.
NOTIFY_DEBUG=1

# Do not install the bridge extension in VSCode/Cursor.
NOTIFY_BRIDGE=0
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

```
/plugin uninstall notify@claude-notifications
```

removes the plugin. To also take the dedicated app, the bridge extension, the state and
whatever a 1.x install left behind, run from a clone of the repo:

```bash
./uninstall.sh
```

Hooks from other tools in `settings.json` are left intact (a timestamped backup is taken
first). If you had applied the icon to Homebrew's shared terminal-notifier:
`brew reinstall terminal-notifier` restores the original.

## Development

```bash
brew install shellcheck bats-core
shellcheck -x -P SCRIPTDIR -S style install.sh uninstall.sh install-notifier-app.sh set-claude-icon.sh vscode-bridge/build-vsix.sh skills/notify/*.sh skills/notify/lang/*.sh tests/helpers.bash
bats tests
claude plugin validate .
```

CI (GitHub Actions) runs shellcheck and `claude plugin validate` on Ubuntu and bats on a
macOS runner. The tests use a throwaway `HOME` and stubs for `claude`, `terminal-notifier`,
`osascript` and `lsappinfo`: no test fires a real notification, installs a plugin or touches
your `settings.json`.

To try local changes as a plugin: `./install.sh --local` installs from the clone, which
Claude Code loads in place (edits apply at the next session or with `/reload-plugins`). Or, for
one session only: `claude --plugin-dir .`.

**Release**: bump `VERSION` and `.claude-plugin/plugin.json`'s `version` together (a test
checks); changing that number is what makes Claude Code offer the update. Tag `v<version>` on
the same commit.

### Adding a language

Copy `skills/notify/lang/en.sh` to `skills/notify/lang/<code>.sh` (the two-letter language code, e.g. `es` or
`fr`), translate the values, and that is it — no script changes, and anyone whose macOS is set
to that language is served automatically. Two tests guard the rest: the catalogues must define
exactly the same keys, and every `$L_*` used by a script must exist in all of them. That
matters because a missing key raises **no** error — the string simply comes out empty.

When translating buttons, keep the shortcut as the initial of the translated word (the format
is `Label:key:token`); that is what keeps the underlined letter and the key in agreement.

## License

Code under [MIT](LICENSE). The logo (`assets/claude-logo.png`/`.svg`) is an Anthropic
trademark, used only to identify Claude Code notifications — not covered by the MIT license.
