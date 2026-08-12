#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$(mktemp -d)"
FAKE_BIN="${FIXTURE_DIR}/bin"
NPM_LOG="${FIXTURE_DIR}/npm.log"
MOCK_OPENCODE_VERSION="1.18.17"
export FAKE_BIN NPM_LOG MOCK_OPENCODE_VERSION

cleanup() {
  rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"

cat > "${FAKE_BIN}/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$NPM_LOG"
cat > "${FAKE_BIN}/opencode" <<'OPENCODE'
#!/usr/bin/env bash
printf '%s\n' "$MOCK_OPENCODE_VERSION"
OPENCODE
chmod +x "${FAKE_BIN}/opencode"
EOF
chmod +x "${FAKE_BIN}/npm"

run_setup() {
  PATH="${FAKE_BIN}:/usr/bin:/bin" \
    OPENCODE_API_KEY="test-key" \
    OPENCODE_VERSION="1.18.17" \
    "$SCRIPT_DIR/setup-opencode.sh"
}

run_setup
grep -Fxq -- "install --global --no-audit --no-fund opencode-ai@1.18.17" "$NPM_LOG"

: > "$NPM_LOG"
run_setup
if [ -s "$NPM_LOG" ]; then
  echo "Expected an exact preinstalled OpenCode version to skip npm installation" >&2
  exit 1
fi

cat > "${FAKE_BIN}/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "1.18.16"
EOF
chmod +x "${FAKE_BIN}/opencode"

run_setup
grep -Fxq -- "install --global --no-audit --no-fund opencode-ai@1.18.17" "$NPM_LOG"

echo "✅ setup-opencode.sh installs and verifies the pinned CLI version"
