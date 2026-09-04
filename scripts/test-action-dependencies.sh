#!/usr/bin/env bash
set -euo pipefail

ACTION_FILE="${ACTION_FILE:-action.yml}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

assert_count() {
  local expected="$1"
  local pattern="$2"
  local description="$3"
  local actual

  actual=$(grep -Ec "$pattern" "$ACTION_FILE" || true)
  if [ "$actual" -ne "$expected" ]; then
    fail "expected ${expected} ${description}, found ${actual}"
  fi
}

[ -f "$ACTION_FILE" ] || fail "action metadata not found: $ACTION_FILE"

# Each external action is a reviewed, immutable input. The release comment makes
# the pin human-readable and keeps dependency-update tooling able to track it.
assert_count 1 \
  '^[[:space:]]*uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7\.0\.0$' \
  'setup-node v7.0.0 pin'
assert_count 1 \
  '^[[:space:]]*uses: actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3 # v9\.0\.0$' \
  'github-script v9.0.0 pin'
assert_count 2 \
  '^[[:space:]]*uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7\.0\.1$' \
  'upload-artifact v7.0.1 pins'
assert_count 1 \
  "^[[:space:]]*node-version: '22'$" \
  'Node.js 22 runtime declaration'

external_uses=$(grep -E '^[[:space:]]*uses:' "$ACTION_FILE" | grep -Ev '^[[:space:]]*uses:[[:space:]]+\./' || true)
external_count=$(printf '%s\n' "$external_uses" | sed '/^$/d' | wc -l | tr -d ' ')
pinned_count=$(printf '%s\n' "$external_uses" | grep -Ec '@[0-9a-f]{40}([[:space:]]+#.*)?$' || true)

if [ "$external_count" -ne "$pinned_count" ]; then
  echo "External action references:" >&2
  printf '%s\n' "$external_uses" >&2
  fail "all external composite-action dependencies must use full 40-character commit SHAs"
fi

if grep -Eq "actions/setup-node@v4|actions/github-script@v7|actions/upload-artifact@v4|node-version:[[:space:]]*['\"]?20(['\"]|$)" "$ACTION_FILE"; then
  fail 'legacy Node.js 20-era action dependency detected'
fi

echo 'Composite action dependencies are immutable and Node.js 24-runner compatible.'
