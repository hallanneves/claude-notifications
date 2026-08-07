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
  cp "$REPO/install.sh" "$REPO/uninstall.sh" "$REPO/hooks.json" "$WORK/repo/"
  cp -R "$REPO/skill" "$WORK/repo/skill"
}

# Replace the copied notify.sh with a recorder: argv goes to $WORK/notify.calls
# instead of posting a real banner.
stub_notify() {
  cat > "$WORK/skill/notify.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "$WORK/notify.calls"
printf -- '---\n' >> "$WORK/notify.calls"
EOF
  chmod +x "$WORK/skill/notify.sh"
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

# osascript stub: records argv to $WORK/osascript.calls, prints $OSA_RESULT.
stub_osascript() {
  cat > "$STUB/osascript" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "$WORK/osascript.calls"
printf '%s' "\${OSA_RESULT:-}"
EOF
  chmod +x "$STUB/osascript"
}

# open stub: records argv so tests can assert the editor would be focused.
stub_open() {
  cat > "$STUB/open" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >> "$WORK/open.calls"
EOF
  chmod +x "$STUB/open"
}
