# Shared setup for the bats suite. Every test gets an isolated fake HOME and a
# stub bin dir prepended to PATH — no test may touch the real user environment
# or fire a real notification.

common_setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d)"
  STUB="$WORK/bin"
  mkdir -p "$STUB"
  # jq must survive the restricted PATH used by the tests
  ln -s "$(command -v jq)" "$STUB/jq"
  export HOME="$WORK/home"
  mkdir -p "$HOME"
  # Pinned so assertions never depend on the machine's locale; i18n.bats is
  # the suite that varies it on purpose.
  export NOTIFY_LANG=pt
  # The host is detected from the environment, so the terminal running the
  # suite must not leak into it: each test states the host it simulates.
  unset __CFBundleIdentifier TERM_PROGRAM ITERM_SESSION_ID TMUX TMUX_PANE \
    CLAUDE_CODE_SSE_PORT HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_BIN_PATH \
    HERDR_TAB_ID HERDR_WORKSPACE_ID NOTIFY_ACTIVATE NOTIFY_STATE_DIR CLAUDE_PLUGIN_DATA
  # Where the scripts keep their state under this fake HOME.
  # shellcheck disable=SC2034  # used by the test files
  STATE="$HOME/Library/Application Support/claude-notifications"
  # The process tree comes from a fixture ($WORK/ps.table, see fake_ps), never
  # from the machine running the suite, which may itself be inside herdr or
  # tmux. Every other ps call (repeat.sh checks its own pids) is the real one.
  cat > "$STUB/ps" <<EOF
#!/bin/bash
if [ "\$*" = "-axo pid=,ppid=,tty=,comm=" ]; then
  [ -f "$WORK/ps.table" ] && cat "$WORK/ps.table"
  exit 0
fi
exec /bin/ps "\$@"
EOF
  chmod +x "$STUB/ps"
  # No test may reach the herdr the developer is running: this one only
  # records. FAKE_HERDR_LIST / FAKE_HERDR_GET are the JSON it answers with.
  cat > "$STUB/herdr" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$WORK/herdr.calls"
case "\$1 \$2" in
  "agent list") [ -n "\${FAKE_HERDR_LIST:-}" ] && { printf '%s' "\$FAKE_HERDR_LIST"; exit 0; } ;;
  "agent get")  [ -n "\${FAKE_HERDR_GET:-}" ] && { printf '%s' "\$FAKE_HERDR_GET"; exit 0; } ;;
  "agent focus") exit "\${FAKE_HERDR_FOCUS_RC:-0}" ;;
esac
echo '{"error":{"code":"agent_not_found"}}' >&2
exit 1
EOF
  chmod +x "$STUB/herdr"
  # Stubs first even in suites that keep the full PATH (restrict_path narrows
  # it further): otherwise those would read the real process tree.
  export PATH="$STUB:$PATH"
  # Only stub_claude's fake may run as `claude`: a real one would install a
  # plugin from GitHub.
  export NOTIFY_CLAUDE="$STUB/claude"
  # Nor may the scripts widen PATH to the machine's Homebrew and editor CLIs.
  export NOTIFY_EXTRA_PATH=""
  # The real idle time is whatever the developer is doing right now; pin it.
  # FAKE_IDLE_SECS simulates someone away from the keyboard.
  cat > "$STUB/ioreg" <<'EOF'
#!/bin/bash
echo "    |   \"HIDIdleTime\" = $(( ${FAKE_IDLE_SECS:-0} * 1000000000 ))"
EOF
  chmod +x "$STUB/ioreg"
}

common_teardown() {
  rm -rf "$WORK"
}

restrict_path() {
  export PATH="$STUB:/usr/bin:/bin"
}

# Disposable copy of the skill so scripts never run against the repo files.
copy_skill() {
  cp -R "$REPO/skills/notify" "$WORK/skill"
}

# Disposable copy of the plugin: everything but the docs and the tests.
copy_repo() {
  mkdir -p "$WORK/repo/skills"
  cp "$REPO/install.sh" "$REPO/uninstall.sh" "$REPO/install-notifier-app.sh" \
    "$REPO/set-claude-icon.sh" "$REPO/VERSION" "$WORK/repo/"
  cp -R "$REPO/.claude-plugin" "$REPO/hooks" "$REPO/assets" "$REPO/vscode-bridge" "$WORK/repo/"
  cp -R "$REPO/skills/notify" "$WORK/repo/skills/notify"
}

# A pre-2.0 install: its copy under ~/.claude/skills/notify and its hooks in
# ~/.claude/settings.json, next to other tools' hooks.
make_legacy_install() {
  mkdir -p "$HOME/.claude/skills/notify"
  cp -R "$REPO/skills/notify/." "$HOME/.claude/skills/notify/"
  jq -n '{hooks: {
      Stop: [{hooks: [{type: "command", command: "\"$HOME/.claude/skills/notify/stop-hook.sh\"", async: true}]},
             {hooks: [{type: "command", command: "other-tool.sh"}]}],
      PermissionRequest: [{hooks: [{type: "command", command: "\"$HOME/.claude/skills/notify/approval-hook.sh\"", timeout: 90}]}],
      PreToolUse: [{hooks: [{type: "command", command: "linter.sh"}]}]
    }}' > "$HOME/.claude/settings.json"
}

# claude stub: records argv to $WORK/claude.calls and keeps the files the
# scripts read (installed_plugins.json, known_marketplaces.json) the way the
# real CLI writes them. FAKE_CLAUDE_FAIL=1 makes `plugin install` fail.
stub_claude() {
  sed "s|@WORK@|$WORK|g" > "$STUB/claude" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >> "@WORK@/claude.calls"
P="$HOME/.claude/plugins"
mkdir -p "$P"
case "$1 $2" in
  "plugin install")
    [ "${FAKE_CLAUDE_FAIL:-0}" = 1 ] && { echo "install failed" >&2; exit 1; }
    src=""
    while [ $# -gt 0 ]; do [ "$1" = "--marketplace" ] && src="$2"; shift; done
    case "$src" in
      /*) jq -n --arg p "$src" '{"claude-notifications": {source: {source: "directory", path: $p}}}' ;;
      *)  jq -n --arg r "$src" '{"claude-notifications": {source: {source: "github", repo: $r}}}' ;;
    esac > "$P/known_marketplaces.json"
    jq -n '{version: 2, plugins: {"notify@claude-notifications": [{scope: "user", version: "2.0.0"}]}}' \
      > "$P/installed_plugins.json" ;;
  "plugin uninstall") echo '{"version": 2, "plugins": {}}' > "$P/installed_plugins.json" ;;
  "plugin marketplace") echo '{}' > "$P/known_marketplaces.json" ;;
esac
exit 0
STUBEOF
  chmod +x "$STUB/claude"
}

# Replace the copied notify.sh with a recorder: argv goes to $WORK/notify.calls
# instead of posting a real banner.
stub_notify() {
  cat > "$WORK/skill/notify.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "$WORK/notify.calls"
printf 'NOTIFY_EXECUTE=%s\n' "\${NOTIFY_EXECUTE:-}" >> "$WORK/notify.calls"
printf 'NOTIFY_GROUP=%s\n' "\${NOTIFY_GROUP:-}" >> "$WORK/notify.calls"
printf -- '---\n' >> "$WORK/notify.calls"
EOF
  chmod +x "$WORK/skill/notify.sh"
}

# lsappinfo stub: FAKE_FRONT controls the frontmost app's name, and its bundle
# id follows from it (FAKE_FRONT_BUNDLE overrides). FAKE_FRONT_FILE, when it
# exists, wins and is re-read on every call: the user switching apps while a
# dialog is open.
stub_lsappinfo() {
  cat > "$STUB/lsappinfo" <<'EOF'
#!/bin/bash
if [ -n "${FAKE_FRONT_FILE:-}" ] && [ -f "$FAKE_FRONT_FILE" ]; then
  FAKE_FRONT="$(cat "$FAKE_FRONT_FILE")"
fi
case "${1:-}" in
  front) echo 'ASN:0x0-0x1:' ;;
  info)
    case "$*" in
      *bundleid*)
        case "${FAKE_FRONT:-Code}" in
          Code)     b="com.microsoft.VSCode" ;;
          Terminal) b="com.apple.Terminal" ;;
          iTerm2)   b="com.googlecode.iterm2" ;;
          Slack)    b="com.tinyspeck.slackmacgap" ;;
          *)        b="com.example.${FAKE_FRONT:-x}" ;;
        esac
        echo "\"CFBundleIdentifier\"=\"${FAKE_FRONT_BUNDLE:-$b}\"" ;;
      *) echo "\"LSDisplayName\"=\"${FAKE_FRONT:-Code}\"" ;;
    esac ;;
esac
EOF
  chmod +x "$STUB/lsappinfo"
}

# A fake .app with a real Info.plist: fake_app <Name> <bundle id>. Prints the
# path of its executable, as ps would show it.
fake_app() {
  local app="$WORK/apps/$1.app"
  mkdir -p "$app/Contents/MacOS"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>\n' \
    "$2" > "$app/Contents/Info.plist"
  printf '%s' "$app/Contents/MacOS/$1"
}

# The process table detect_origin and herdr_clients read: one
# "pid ppid tty comm" line per process. Tests start the walk at NOTIFY_PID.
fake_ps() {
  printf '%s\n' "$@" > "$WORK/ps.table"
}

# osascript stub: records argv to $WORK/osascript.calls and prints $OSA_RESULT
# (the token the real dialog.js would print). OSA_DELAY simulates a user who
# never answers, so the caller's timeout can be exercised. A script read from
# stdin (`osascript - args`) goes to $WORK/osascript.scripts, apart from argv,
# so a test can prove a value travelled as an argument and not inside the code.
# OSA_ERR makes it fail with that text on stderr, as a refused Apple Event does.
stub_osascript() {
  cat > "$STUB/osascript" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "$WORK/osascript.calls"
[ "\${1:-}" = "-" ] && cat >> "$WORK/osascript.scripts"
if [ -n "\${OSA_ERR:-}" ]; then
  printf '%s\n' "\$OSA_ERR" >&2
  exit 1
fi
[ -n "\${OSA_DELAY:-}" ] && sleep "\$OSA_DELAY"
printf '%s' "\${OSA_RESULT:-}"
EOF
  chmod +x "$STUB/osascript"
}

# A Claude Code IDE lock file, as the editor extension writes one per running
# window group: make_ide_lock <pid> <workspace folder>...
make_ide_lock() {
  local pid="$1"; shift
  mkdir -p "$HOME/.claude/ide"
  jq -n --argjson pid "$pid" '{pid: $pid, workspaceFolders: $ARGS.positional, ideName: "Visual Studio Code"}' \
    --args "$@" > "$HOME/.claude/ide/$RANDOM$RANDOM.lock"
}

# open stub: records argv so tests can assert the editor would be focused.
stub_open() {
  cat > "$STUB/open" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "$WORK/open.calls"
EOF
  chmod +x "$STUB/open"
}
