#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
CHECKER="${SCRIPT_DIR}/check-workflow-policy.sh"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

expect_rejected() {
  local description="$1"
  local fixture_root="$2"

  if "$CHECKER" "$fixture_root" >/dev/null 2>&1; then
    fail "unsafe fixture was accepted: $description"
  fi
}

make_fixture() {
  local fixture_root
  fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/validator-workflow-policy.XXXXXX")
  mkdir -p "$fixture_root/.github"
  mkdir -p "$fixture_root/scripts"
  cp "$REPOSITORY_ROOT/action.yml" "$fixture_root/action.yml"
  cp -R "$REPOSITORY_ROOT/.github/workflows" "$fixture_root/.github/workflows"
  printf '%s\n' "$fixture_root"
}

"$CHECKER" "$REPOSITORY_ROOT"

fixture=$(make_fixture)
sed -i.bak 's#actions/checkout@[0-9a-f]\{40\} #actions/checkout@v7 #' "$fixture/.github/workflows/test.yml"
expect_rejected 'moving major action tag' "$fixture"
rm -rf "$fixture"

fixture=$(make_fixture)
printf '%s\n' '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' >> "$fixture/.github/workflows/test.yml"
expect_rejected 'missing reviewed version comment' "$fixture"
rm -rf "$fixture"

fixture=$(make_fixture)
sed -i.bak 's/contents: read/contents: write/' "$fixture/.github/workflows/release-please.yml"
expect_rejected 'broad release job-token permission' "$fixture"
rm -rf "$fixture"

fixture=$(make_fixture)
sed -i.bak 's/client-id:/app-id:/' "$fixture/.github/workflows/release-please.yml"
expect_rejected 'deprecated GitHub App ID input' "$fixture"
rm -rf "$fixture"

fixture=$(make_fixture)
sed -i.bak 's/RELEASE_PLEASE_APP_PRIVATE_KEY/FLOWCORE_MACHINE_GITHUB_TOKEN/' "$fixture/.github/workflows/release-please.yml"
expect_rejected 'legacy shared PAT' "$fixture"
rm -rf "$fixture"

fixture=$(make_fixture)
sed -i.bak 's#releases/download/${YQ_VERSION}/#releases/latest/download/#' "$fixture/.github/workflows/test.yml"
expect_rejected 'moving executable download URL' "$fixture"
rm -rf "$fixture"

fixture=$(make_fixture)
sed -i.bak 's/c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' "$fixture/.github/workflows/test.yml"
expect_rejected 'unreviewed yq checksum' "$fixture"
rm -rf "$fixture"

fixture=$(make_fixture)
printf '%s\n' '#!/usr/bin/env bash' 'git push origin refs/tags/latest --force' > "$fixture/scripts/unsafe-promotion.sh"
expect_rejected 'latest mutation outside protected workflow' "$fixture"
rm -rf "$fixture"

fixture=$(make_fixture)
printf '%s\n' '          ${{ needs.check-trigger.outputs.comment-body }}' >> "$fixture/.github/workflows/comment-revalidation.yml"
expect_rejected 'untrusted comment interpolation into shell' "$fixture"
rm -rf "$fixture"

echo 'Workflow policy rejects moving dependencies, legacy credentials, broad permissions, and unverified downloads.'
