#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECKER="${SCRIPT_DIR}/check-no-hardcoded-secrets.sh"

expect_rejected() {
  local value="$1"
  local fixture
  fixture=$(mktemp "${TMPDIR:-/tmp}/validator-secret-policy.XXXXXX.yml")
  printf '%s\n' "$value" > "$fixture"
  if "$CHECKER" "$fixture" >/dev/null 2>&1; then
    echo "ERROR: hardcoded credential fixture was accepted" >&2
    rm -f "$fixture"
    exit 1
  fi
  rm -f "$fixture"
}

"$CHECKER" "${SCRIPT_DIR}" "${SCRIPT_DIR}/../.github"

expect_rejected 'token: abcdefghijklmnopqrstuvwxyz012345'
expect_rejected 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF'
expect_rejected 'github_token: github_pat_1234567890abcdefghijklmnop'
expect_rejected '-----BEGIN PRIVATE KEY-----'

safe_fixture=$(mktemp "${TMPDIR:-/tmp}/validator-secret-policy-safe.XXXXXX.yml")
printf '%s\n' 'token: ${{ steps.app-token.outputs.token }}' > "$safe_fixture"
"$CHECKER" "$safe_fixture" >/dev/null
rm -f "$safe_fixture"

echo 'Secret policy rejects credential-shaped literals and accepts GitHub expression references.'
