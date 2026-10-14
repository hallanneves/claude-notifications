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
    CLAUDE_CODE_SSE_PORT HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH NOTIFY_ACTIVATE
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
}

# Replace the copied notify.sh with a recorder: argv goes to $WORK/notify.calls
# instead of posting a real banner.
stub_notify() {
  cat > "$WORK/skill/notify.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "$WORK/notify.calls"
printf 'NOTIFY_EXECUTE=%s\n' "\${NOTIFY_EXECUTE:-}" >> "$WORK/notify.calls"
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

# lsappinfo stub: FAKE_FRONT controls the reported frontmost app name.
stub_lsappinfo() {
  cat > "$STUB/lsappinfo" <<'EOF'
#!/bin/bash
case "${1:-}" in
  front) echo 'ASN:0x0-0x1:' ;;
  info)  echo "\"LSDisplayName\"=\"${FAKE_FRONT:-Code}\"" ;;
esac
EOF
  chmod +x "$STUB/lsappinfo"
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
