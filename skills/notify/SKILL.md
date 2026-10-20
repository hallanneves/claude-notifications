---
name: notify
description: Native macOS notifications (banner + sound, Slack-style) for Claude Code. Use for /notify, and whenever the user asks to be told when something finishes — "notify me when X is done", "let me know when the build/tests/deploy/CI finishes", "ping me when it's ready", "me avisa/notifica quando X terminar" — for periodic reminders ("remind me every 30 min", "me lembra a cada 30 min"), for periodic work status ("keep me posted", "vai me mandando o status"), to stop active reminders (/notify stop, /notify list), to silence notifications for focused work ("mute notifications", "stop notifying me for an hour", "silencia as notificações", "modo foco") and to turn them back on, to finish the move from the old install (/notify migrate), or to find out why a notification did or did not show (/notify doctor). Semantic sounds per event type (approval/info/done/failure); Claude icon on the banner; no emojis in messages. Interface strings are bilingual (English/Portuguese).
---

# notify — native macOS notifications

Scripts in this skill's directory, `${CLAUDE_SKILL_DIR}` (part of the `notify` plugin from the
`claude-notifications` marketplace):

- `notify.sh [--approval|--info|--done|--fail] "message" ["title"] ["subtitle"] ["sound"]` —
  a banner, now. The type presets a title + sound; an explicit title/sound overrides it.
- `repeat.sh <seconds> "message" ["title"]` — detached periodic reminder (survives the
  session). `repeat.sh stop` kills them all; `repeat.sh list` lists them.
- `mute.sh [30m|2h|on|off|status]` — focus mode. Silences banners AND the approval dialog.
- `migrate.sh` — retires a pre-2.0 install (its hooks in `~/.claude/settings.json`, its copy in
  `~/.claude/skills/notify`), moving its config and state over. Until it runs, the plugin's
  hooks stand by so nothing fires twice.
- `setup.sh` — creates the notifier app and installs the VSCode bridge. The `SessionStart` hook
  runs it on its own once per version; run it by hand only when `doctor.sh` says so.
- `doctor.sh [--test]` — where this session runs, whether the user counts as "looking", where
  a click would land, the notifier's health, herdr hints. `--test` posts a banner and reports
  what the click did. Use it whenever the user asks why something did or did not notify.
- `notify-hook.sh` / `stop-hook.sh` / `approval-hook.sh` / `prompt-hook.sh` / `session-hook.sh`
  — hook adapters (Notification / Stop / PermissionRequest / UserPromptSubmit / SessionStart),
  declared in the plugin's `hooks/hooks.json`. Not called by the skill.

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
bash "${CLAUDE_SKILL_DIR}/notify.sh" "<message>"
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
bash "${CLAUDE_SKILL_DIR}/repeat.sh" <interval_in_seconds> "<message>"
```

- Detached process: it outlives the session. Report the PID and how to stop it.
- `/notify stop` → `repeat.sh stop` · `/notify list` → `repeat.sh list`
- `repeat.sh` is ONLY for a fixed message (a reminder). For work status use mode 4 — never
  freeze a "status" inside a repeat.

### 4. Work status every so often — "keep me posted"

When the user asks for periodic progress on ongoing work, YOU compose each message, at the
time, from the real state — one short `--info` per check:

```bash
bash "${CLAUDE_SKILL_DIR}/notify.sh" "Migration: 3 of 7 files done, tests passing" "Work status"
```

- **You are doing the work**: fire at each completed milestone (a phase, a suite, a big file),
  roughly aiming at the requested interval. Changed direction or got stuck? That IS status.
- **Background work** (long suite, workflow, agent, CI): schedule periodic checks
  (ScheduleWakeup/Monitor, interval proportional to the job) and send the real summary on each
  wake-up; close with `--done`/`--fail` (mode 2).
- Content: one concrete line (what is done, what is running, a count or % if there is one).
  Never invent progress — if there is no news, say so ("still on the integration suite, no
  failures so far").

### 5. Moving from the old install — `/notify migrate`

```bash
bash "${CLAUDE_SKILL_DIR}/migrate.sh"
```

- Needed only when the `SessionStart` message (or `doctor.sh`) says the old install is still
  wired. Report what it printed, and tell the user to **restart the Claude Code sessions already
  open**: they started with the old hooks and keep calling them.
- Updates come from the plugin system now: `/plugin` → Marketplaces → `claude-notifications` →
  **Enable auto-update** (off by default for third-party marketplaces), or `/plugin update`.

### 5b. Diagnosis — `/notify doctor`

```bash
bash "${CLAUDE_SKILL_DIR}/doctor.sh"          # read-only report
bash "${CLAUDE_SKILL_DIR}/doctor.sh" --test   # also posts a banner; the user clicks it
```

### 6. Focus mode — "mute for an hour" / "stop notifying me"

```bash
bash "${CLAUDE_SKILL_DIR}/mute.sh" 30m     # 45s, 30m, 2h, 1d; bare number = minutes
bash "${CLAUDE_SKILL_DIR}/mute.sh" on      # until turned off
bash "${CLAUDE_SKILL_DIR}/mute.sh" off
bash "${CLAUDE_SKILL_DIR}/mute.sh" status
```

- Muting covers banners, reminders **and the approval dialog** — while
  muted, a permission request falls back to the terminal prompt and waits quietly there.
- Always report back when it ends (or that it lasts until turned off), so nobody is left
  wondering why approvals stopped popping.

## Hooks (automatic, no invocation)

Declared by the plugin (`hooks/hooks.json`):
- **SessionStart** → `session-hook.sh`: runs `setup.sh` in the background the first time a
  session starts on a new version, says once how to turn on auto-updates, and while a pre-2.0
  install is still wired asks for `/notify migrate`.
- **Notification** → `notify-hook.sh`: routes on `notification_type`. On `permission_prompt`
  it stays silent when approval-hook.sh already announced that session's request (a
  per-session stamp) — otherwise one request means two banners and two sonar sounds — and
  speaks when it did not. Unknown types are a plain info banner, never the approval sonar.
- Clicking any notification returns to where it came from, never to another app: the exact
  terminal tab (iTerm2 by session id, Terminal.app by tty) when the host exposes one; in an
  editor, the window holding the project, opened by its workspace root from
  `~/.claude/ide/*.lock` (a subfolder would open a new window); otherwise the app hosting the
  session. A refused Automation permission posts one notice. `NOTIFY_ACTIVATE_PATH=never`
  restores plain app focus.
- **Stop** → `stop-hook.sh`: "<project> · done" banner at the end of a turn, with the first
  line of Claude's answer (`NOTIFY_PREVIEW=off` hides it) and Glass, not Hero. **Suppressed**
  while the user is watching THAT session — the app showing it frontmost (VSCode in front of a
  Terminal session does not count), input in the last `NOTIFY_AWAY_SECS` (60s), and under
  herdr its pane on screen — and for turns under `NOTIFY_MIN_TURN_SECS` (30s).
  `NOTIFY_FORCE=1` bypasses the gate.
- **UserPromptSubmit** → `prompt-hook.sh` (async): starts the turn clock and removes the
  session's notifications from Notification Center. Every notification of a session shares a
  group (`claude-<session_id>`), so a new one replaces the last.
- Where a session runs is read from the **process tree** (herdr, tmux, an editor's extension
  host or integrated terminal, or an app), not from environment variables, which multiplexers
  leak. Under herdr a click focuses the session's pane (looked up by session id) and the
  Terminal/iTerm2 tab running the herdr client. In VSCode/Cursor the bridge extension
  (`vscode-bridge/`, installed by `setup.sh`) reveals the session's Claude tab or its
  integrated terminal, in the window that owns it; without the bridge the click stops at the
  project's window.
- **PermissionRequest** → `approval-hook.sh`: when the user is not watching, a floating
  panel (`dialog.js`) that never takes the keyboard, titled with the project and branch,
  showing the exact command in a scrolling box (control/bidi characters rendered as
  `⟨U+XXXX⟩`), with Approve (click only — no key ever approves) / "Always approve: <rule>"
  (only when Claude Code offers `permission_suggestions`; the suggestion is returned verbatim
  as `updatedPermissions`) / **D**eny / **G**o to session / Close (**Esc**). Letter shortcuts
  work once the user clicks into the panel. One panel at a time (parallel sessions queue), and
  it closes unanswered when the user looks at the session again. It returns the decision to
  Claude Code (allow and deny confirmed live). AskUserQuestion and ExitPlanMode get a "your turn" banner instead of a dialog. Close/
  Esc, timeout (`NOTIFY_DIALOG_TIMEOUT`, default 50s) and any error fall back to the normal
  terminal prompt (fail-safe). An already-allowlisted command raises no prompt → the hook
  never runs (not a bug).

## Gotchas

- The poster is `~/Applications/Claude Code Notifier.app` (created by `setup.sh` through the
  plugin's `install-notifier-app.sh`): it carries the notification permission and the Claude icon.
  Clicking a notification focuses the app hosting the session (`NOTIFY_ACTIVATE` overrides).
- **A notification that "sends" but never appears**: running terminal-notifier straight from
  the Homebrew keg, macOS never asks for permission, accepts the notification (it shows up in
  `-list ALL`) and drops the banner silently — all with `exit 0` and no error anywhere. The
  dedicated app is what fixes it. The `-sender` (hangs the process, never delivers) and
  `-appIcon` (ignored) flags are no help.
- **The approval banner omits the command by default** (`NOTIFY_BANNER_DETAIL=tool`): macOS
  shows notification previews on the lock screen, and a command can carry a token. The full
  command is in the dialog, which needs an unlocked session. `full` restores it in the banner.
- Optional config in `~/Library/Application Support/claude-notifications/notify.conf` (see
  `notify.conf.example`; outside the plugin, so updates keep it):
  `NOTIFY_LANG`, `NOTIFY_ACTIVATE` (click target), `NOTIFY_FRONT_APPS` (extra apps that
  suppress the "done" banner and the dialog), `NOTIFY_AWAY_SECS` (idle seconds that count as
  away), `NOTIFY_TN` (the posting binary),
  `NOTIFY_BANNER_DETAIL`, `NOTIFY_DIALOG_TIMEOUT`, `NOTIFY_BRIDGE=0` (no VSCode bridge).
  `repeat.sh` requires a whole interval >= 5s, and `stop` only kills processes carrying the
  `claude-notify-repeat` marker (a recycled PID is never a target).
- Without terminal-notifier the fallback is `osascript`: the banner is posted as "Script
  Editor" and clicking it opens an empty Script Editor window (a macOS quirk).
- The approval dialog is a non-activating NSPanel (JXA), shown with `orderFrontRegardless`
  and no `runModal` (a modal session would make it the key window and take the keyboard).
  Not an NSAlert: that one activates its app, so typing elsewhere landed in it.
- The dialog timeout lives in the **shell**, which kills the process. The watchdog runs with
  stdout redirected — otherwise it holds the caller's pipe and the decision only arrives when
  the whole timeout elapses, even if answered in 2s.
- **Nothing appears at all**: System Settings → Notifications → allow the app ("Claude Code",
  or "Script Editor" on the fallback) with the style set to Banners/Alerts, never "None".
  Focus/Do Not Disturb silences it.
- Quotes in a message are safe — the scripts escape before AppleScript.
- `NOTIFY_DEBUG=1` appends one line per hook call to `.debug.log` in the state directory. Every
  error path exits 0 in silence by design, so this is the way to see what happened.
- Canonical source: the `hallanneves/claude-notifications` repo on GitHub, which is also the
  plugin's marketplace (`/plugin install notify --marketplace hallanneves/claude-notifications`).
