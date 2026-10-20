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
  # Nothing in the suite may reach the network. The Stop hook runs the update
  # check in the background, and a real `git ls-remote` against GitHub posts
  # its banner through the same stubs, racing whatever the test asserts. Tests
  # of the update check pass their own fake remote.
  export NOTIFY_UPDATE_REPO="$WORK/no-remote"
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
  cp -R "$REPO/skill" "$WORK/skill"
}

# Disposable copy of the repo pieces the installer needs.
copy_repo() {
  mkdir -p "$WORK/repo"
  cp "$REPO/install.sh" "$REPO/uninstall.sh" "$REPO/hooks.json" "$REPO/VERSION" "$WORK/repo/"
  cp -R "$REPO/skill" "$WORK/repo/skill"
  cp -R "$REPO/assets" "$WORK/repo/assets"
  cp -R "$REPO/vscode-bridge" "$WORK/repo/vscode-bridge"
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

# A throwaway git repo standing in for the upstream remote, tagged as given.
make_fake_remote() {
  local dir="$WORK/remote" tag
  mkdir -p "$dir"
  git init -q "$dir"
  git -C "$dir" config user.email t@t
  git -C "$dir" config user.name t
  echo x > "$dir/a.txt"
  git -C "$dir" add a.txt
  git -C "$dir" commit -qm init
  for tag in "$@"; do git -C "$dir" tag "$tag"; done
  printf '%s' "$dir"
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
