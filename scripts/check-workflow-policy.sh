#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="${1:-.}"
ACTION_FILE="${REPOSITORY_ROOT}/action.yml"
WORKFLOW_DIR="${REPOSITORY_ROOT}/.github/workflows"
RELEASE_WORKFLOW="${WORKFLOW_DIR}/release-please.yml"
TEST_WORKFLOW="${WORKFLOW_DIR}/test.yml"
REVALIDATION_WORKFLOW="${WORKFLOW_DIR}/comment-revalidation.yml"
SCRIPT_DIR="${REPOSITORY_ROOT}/scripts"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for required_path in "$ACTION_FILE" "$WORKFLOW_DIR" "$RELEASE_WORKFLOW" "$TEST_WORKFLOW"; do
  [ -e "$required_path" ] || fail "required policy input not found: $required_path"
done

policy_files=("$ACTION_FILE")
while IFS= read -r workflow_file; do
  policy_files+=("$workflow_file")
done < <(find "$WORKFLOW_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort)

external_uses=$(grep -H -E '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+' "${policy_files[@]}" \
  | grep -Ev 'uses:[[:space:]]+\./' || true)

unpinned_uses=$(printf '%s\n' "$external_uses" \
  | grep -Ev '@[0-9a-f]{40}[[:space:]]+# v?[0-9]+\.[0-9]+\.[0-9]+$' || true)
if [ -n "$unpinned_uses" ]; then
  echo "Unpinned external action references:" >&2
  printf '%s\n' "$unpinned_uses" >&2
  fail 'every external action must use a reviewed full SHA and semantic-version comment'
fi

if grep -R -E -q \
  'actions/checkout@v[1-9]|actions/github-script@v[1-9]|actions/setup-node@v[1-9]|actions/upload-artifact@v[1-9]|@main([[:space:]]|$)|@master([[:space:]]|$)' \
  "$ACTION_FILE" "$WORKFLOW_DIR"; then
  fail 'moving action reference or legacy Node.js 20-era dependency detected'
fi

if grep -R -E -q "node-version:[[:space:]]*['\"]?20(['\"]|$)" "$ACTION_FILE" "$WORKFLOW_DIR"; then
  fail 'legacy Node.js 20 runtime declaration detected'
fi

if grep -R -F -q 'ludeeus/action-shellcheck' "$WORKFLOW_DIR"; then
  fail 'the ShellCheck action downloads an unverified executable; use the runner binary directly'
fi

if grep -R -F -q '/releases/latest/download/' "$WORKFLOW_DIR"; then
  fail 'moving executable download URL detected'
fi

if [ -d "$SCRIPT_DIR" ]; then
  unauthorized_latest_mutation=$(
    find "$SCRIPT_DIR" -maxdepth 1 -type f \
      ! -name 'check-workflow-policy.sh' \
      ! -name 'test-workflow-policy.sh' \
      ! -name 'test-release-rollout-policy.sh' \
      -exec grep -H -E 'git (push|tag).*latest|latest.*--force' {} + || true
  )
  if [ -n "$unauthorized_latest_mutation" ]; then
    echo "$unauthorized_latest_mutation" >&2
    fail 'latest may move only through the protected promotion workflow'
  fi
fi

for required_release_value in \
  'permissions:' \
  'contents: read' \
  'client-id: ${{ vars.RELEASE_PLEASE_APP_CLIENT_ID }}' \
  'private-key: ${{ secrets.RELEASE_PLEASE_APP_PRIVATE_KEY }}' \
  'token: ${{ steps.app-token.outputs.token }}' \
  'config-file: release-please-config.json' \
  'manifest-file: .release-please-manifest.json'; do
  grep -F -q "$required_release_value" "$RELEASE_WORKFLOW" \
    || fail "release workflow is missing: $required_release_value"
done

if grep -E -q 'FLOWCORE_MACHINE_GITHUB_TOKEN|^[[:space:]]*app-id:|pull-requests:[[:space:]]*write|contents:[[:space:]]*write' "$RELEASE_WORKFLOW"; then
  fail 'release workflow contains a legacy credential or broad workflow-token permission'
fi

for required_yq_value in \
  'YQ_VERSION: v4.53.6' \
  'YQ_SHA256: c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385' \
  'releases/download/${YQ_VERSION}/yq_linux_amd64' \
  'sha256sum --check --status'; do
  grep -F -q "$required_yq_value" "$TEST_WORKFLOW" \
    || fail "pinned yq installation is missing: $required_yq_value"
done

for required_shellcheck_value in \
  'SHELLCHECK_VERSION: v0.11.0' \
  'SHELLCHECK_SHA256: 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198' \
  'releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz' \
  'sha256sum --check --status'; do
  grep -F -q "$required_shellcheck_value" "$TEST_WORKFLOW" \
    || fail "pinned ShellCheck installation is missing: $required_shellcheck_value"
done

for required_actionlint_value in \
  'ACTIONLINT_VERSION: v1.7.12' \
  'ACTIONLINT_SHA256: 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8' \
  'releases/download/${ACTIONLINT_VERSION}/${release_archive}' \
  'sha256sum --check --status'; do
  grep -F -q "$required_actionlint_value" "$TEST_WORKFLOW" \
    || fail "pinned actionlint installation is missing: $required_actionlint_value"
done

for required_revalidation_value in \
  'OVERRIDE_COMMENT: ${{ needs.check-trigger.outputs.comment-body }}' \
  'printf '\''%s\n'\'' "$OVERRIDE_COMMENT"' \
  'PR_BASE_REF: ${{ steps.pr.outputs.base-ref }}' \
  'PR_HEAD_REF: ${{ steps.pr.outputs.head-ref }}' \
  'openssl rand -hex 16'; do
  grep -F -q "$required_revalidation_value" "$REVALIDATION_WORKFLOW" \
    || fail "safe comment revalidation handling is missing: $required_revalidation_value"
done

if grep -F -q '          ${{ needs.check-trigger.outputs.comment-body }}' "$REVALIDATION_WORKFLOW"; then
  fail 'untrusted comment body must not be interpolated into a shell script'
fi

opencode_alias_count=$(grep -F -c 'OPENCODE_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}' "$TEST_WORKFLOW" || true)
if [ "$opencode_alias_count" -ne 3 ]; then
  fail "expected three integration jobs to alias OPENROUTER_API_KEY, found $opencode_alias_count"
fi

if grep -F -q 'OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}' "$TEST_WORKFLOW"; then
  fail 'integration tests reference the nonexistent OPENCODE_API_KEY secret'
fi

echo 'Workflow actions, release credentials, and executable downloads satisfy the immutable dependency policy.'
