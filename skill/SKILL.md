---
name: notify
description: Native macOS notifications (banner + sound, Slack-style) for Claude Code. Use for /notify, and whenever the user asks to be told when something finishes — "notify me when X is done", "let me know when the build/tests/deploy/CI finishes", "ping me when it's ready", "me avisa/notifica quando X terminar" — for periodic reminders ("remind me every 30 min", "me lembra a cada 30 min"), for periodic work status ("keep me posted", "vai me mandando o status"), to stop active reminders (/notify stop, /notify list), or to check for a new version. Semantic sounds per event type (approval/info/done/failure); Claude icon on the banner; no emojis in messages. Interface strings are bilingual (English/Portuguese).
---

# notify — native macOS notifications

Scripts in this directory (`~/.claude/skills/notify/`):

- `notify.sh [--approval|--info|--done|--fail] "message" ["title"] ["subtitle"] ["sound"]` —
  a banner, now. The type presets a title + sound; an explicit title/sound overrides it.
- `repeat.sh <seconds> "message" ["title"]` — detached periodic reminder (survives the
  session). `repeat.sh stop` kills them all; `repeat.sh list` lists them.
- `check-update.sh [--force]` — is a newer version published? Without `--force` it is
  rate-limited (once a day) and speaks only when there is news; with `--force` it always answers.
- `update.sh` — installs the newest tag. This is what the banner's click triggers.
- `notify-hook.sh` / `stop-hook.sh` / `approval-hook.sh` — hook adapters (Notification /
  Stop / PermissionRequest) wired in `~/.claude/settings.json`. Not called by the skill.

## Language

Two things are localized independently, and confusing them is the usual mistake:

- **Interface strings** (banner titles, dialog buttons, hook messages) come from
  `lang/en.sh` and `lang/pt.sh`, chosen by the macOS locale or `NOTIFY_LANG`. When adding any
  new user-facing text, **create the `L_*` key in every catalogue** — the tests fail if one is
  missing, but in production the string would silently render empty.
- **The message YOU write** (the content passed to `/notify`) follows the language of the
  conversation, not the catalogue. A user writing in Portuguese gets a Portuguese message.

## Visual and sound identity (ALWAYS respect)

- **NO emojis** in notification titles or messages. Visual identification comes from the
  **Claude icon** on the banner; the semantics come from **sound + title**.
- Sounds never change meaning: Hero is success only, Basso is failure only.

| Type | Flag | Default title | Sound | When |
|---|---|---|---|---|
| Approval | `--approval` | Approval needed | Submarine | reserved for the hooks |
| Info | `--info` (default) | Claude Code | Glass | a notification the user asked for |
| Done | `--done` | Work finished | Hero | a job finished successfully |
| Failure | `--fail` | Something failed | Basso | a job broke |

## Modes

### 1. Now — `/notify <message>`

```bash
bash ~/.claude/skills/notify/notify.sh "<message>"
```

### 2. When a job finishes — "tell me when X is done"

1. Run the command with Bash `run_in_background: true` (you are re-invoked when it ends).
2. **Check the real exit code / output** and only then notify the true outcome:
   - success: `notify.sh --done "web suite passed (752 tests, 4m)"`
   - failure: `notify.sh --fail "build broke: <one-line summary of the error>"`
   Never send `--done` without verifying.
3. External condition (CI, deploy, a file appearing): poll at an interval proportional to the
   process (a ~10 min job → check every 3–5 min; use ScheduleWakeup/Monitor when available)
   and notify on the state change.

### 3. Every so often — "remind me every X"

```bash
bash ~/.claude/skills/notify/repeat.sh <interval_in_seconds> "<message>"
```

- Detached process: it outlives the session. Report the PID and how to stop it.
- `/notify stop` → `repeat.sh stop` · `/notify list` → `repeat.sh list`
- `repeat.sh` is ONLY for a fixed message (a reminder). For work status use mode 4 — never
  freeze a "status" inside a repeat.

### 4. Work status every so often — "keep me posted"

When the user asks for periodic progress on ongoing work, YOU compose each message, at the
time, from the real state — one short `--info` per check:

```bash
bash ~/.claude/skills/notify/notify.sh "Migration: 3 of 7 files done, tests passing" "Work status"
```

- **You are doing the work**: fire at each completed milestone (a phase, a suite, a big file),
  roughly aiming at the requested interval. Changed direction or got stuck? That IS status.
- **Background work** (long suite, workflow, agent, CI): schedule periodic checks
  (ScheduleWakeup/Monitor, interval proportional to the job) and send the real summary on each
  wake-up; close with `--done`/`--fail` (mode 2).
- Content: one concrete line (what is done, what is running, a count or % if there is one).
  Never invent progress — if there is no news, say so ("still on the integration suite, no
  failures so far").

### 5. Updating — "is there a new version?" / `/notify update`

```bash
bash ~/.claude/skills/notify/check-update.sh --force   # always answers
bash ~/.claude/skills/notify/update.sh                 # update now
```

- The automatic check runs in the `Stop` hook, detached, at most once a day; when a newer tag
  exists it posts a **clickable** banner. The click opens a dialog with **Install / View on
  GitHub / Cancel** — it never installs straight away (this is open source: the user must be
  able to read first). It never says "you are up to date". `update.sh --yes` skips the dialog.
- It installs the exact tag it advertised, from a throwaway clone; your working copy is never
  touched.
- After updating, tell the user the hooks only reload when **Claude Code restarts**.
- Turn it off with `NOTIFY_UPDATE_CHECK=0` in `notify.conf`.

## Hooks (automatic, no invocation)

Configured in `~/.claude/settings.json`:
- **Notification** → `notify-hook.sh`: routes on `notification_type`. It stays silent on
  `permission_prompt` when the PermissionRequest hook is wired, because that one already posts
  a banner — otherwise one request means two banners and two sonar sounds.
- **Stop** → `stop-hook.sh`: "work done" banner at the end of a turn — **suppressed** while
  VSCode/terminal is frontmost (otherwise it fires on every reply). `NOTIFY_FORCE=1` bypasses
  the gate. It also kicks off the rate-limited update check.
- **PermissionRequest** → `approval-hook.sh`: when you are away from the editor, a native
  dialog (NSAlert via `dialog.js`) with **A**pprove / **D**eny / open in **e**ditor / Close,
  each letter underlined as its shortcut and **Esc** to close without deciding. It returns the
  decision to Claude Code (allow and deny confirmed live). Interaction tools (AskUserQuestion
  etc.) are skipped. Close/Esc, timeout (`NOTIFY_DIALOG_TIMEOUT`, default 50s) and any error
  fall back to the normal terminal prompt (fail-safe). An already-allowlisted command raises
  no prompt → the hook never runs (not a bug).

## Gotchas

- The poster is `~/Applications/Claude Code Notifier.app` (created by the repo's
  `install-notifier-app.sh`): it carries the notification permission and the Claude icon.
  Clicking a notification focuses VSCode (`NOTIFY_ACTIVATE` changes the bundle id).
- **A notification that "sends" but never appears**: running terminal-notifier straight from
  the Homebrew keg, macOS never asks for permission, accepts the notification (it shows up in
  `-list ALL`) and drops the banner silently — all with `exit 0` and no error anywhere. The
  dedicated app is what fixes it. The `-sender` (hangs the process, never delivers) and
  `-appIcon` (ignored) flags are no help.
- **The approval banner omits the command by default** (`NOTIFY_BANNER_DETAIL=tool`): macOS
  shows notification previews on the lock screen, and a command can carry a token. The full
  command is in the dialog, which needs an unlocked session. `full` restores it in the banner.
- Optional config in `~/.claude/skills/notify/notify.conf` (see `notify.conf.example`):
  `NOTIFY_LANG`, `NOTIFY_ACTIVATE` (click target), `NOTIFY_FRONT_APPS` (extra apps that
  suppress the "done" banner and the dialog), `NOTIFY_TN` (the posting binary),
  `NOTIFY_BANNER_DETAIL`, `NOTIFY_DIALOG_TIMEOUT` and the `NOTIFY_UPDATE_*` trio.
  `repeat.sh` requires a whole interval >= 5s, and `stop` only kills processes carrying the
  `claude-notify-repeat` marker (a recycled PID is never a target).
- Without terminal-notifier the fallback is `osascript`: the banner is posted as "Script
  Editor" and clicking it opens an empty Script Editor window (a macOS quirk).
- The approval dialog is an NSAlert (JXA), not AppleScript's `display dialog`: that one caps
  at three buttons and has neither per-button shortcuts nor underlined mnemonics. It calls
  `activateIgnoringOtherApps` — without it the window opens behind the focused app.
- The dialog timeout lives in the **shell**, not the JS: a scheduled NSTimer never fires
  during `runModal` (the modal uses `NSModalPanelRunLoopMode`; the timer joins the default
  mode). The watchdog runs with stdout redirected — otherwise it holds the caller's pipe and
  the decision only arrives when the whole timeout elapses, even if answered in 2s.
- **Nothing appears at all**: System Settings → Notifications → allow the app ("Claude Code",
  or "Script Editor" on the fallback) with the style set to Banners/Alerts, never "None".
  Focus/Do Not Disturb silences it.
- Quotes in a message are safe — the scripts escape before AppleScript.
- `NOTIFY_DEBUG=1` appends one line per hook call to `.debug.log` next to the skill. Every
  error path exits 0 in silence by design, so this is the way to see what happened.
- Canonical source / installation: the `hallanneves/claude-notifications` repo on GitHub.
  When changing anything here, mirror it there.
