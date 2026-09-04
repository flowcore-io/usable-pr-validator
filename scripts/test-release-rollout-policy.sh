#!/usr/bin/env bash
set -euo pipefail

RELEASE_WORKFLOW="${RELEASE_WORKFLOW:-.github/workflows/release-please.yml}"
PROMOTION_WORKFLOW="${PROMOTION_WORKFLOW:-.github/workflows/promote-latest.yml}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for workflow in "$RELEASE_WORKFLOW" "$PROMOTION_WORKFLOW"; do
  [ -f "$workflow" ] || fail "workflow not found: $workflow"
done

if grep -Eq 'git (push|tag).*latest|latest.*--force' "$RELEASE_WORKFLOW"; then
  fail 'release-please must not move the shared latest alias automatically'
fi

grep -Eq '^[[:space:]]{2}workflow_dispatch:' "$PROMOTION_WORKFLOW" \
  || fail 'latest promotion must be manually dispatched'
if grep -Eq '^[[:space:]]{2}(push|pull_request|schedule):' "$PROMOTION_WORKFLOW"; then
  fail 'latest promotion must not have an automatic trigger'
fi

for required in \
  'environment: validator-rollout' \
  'contents: write' \
  'release_tag must be an exact stable vMAJOR.MINOR.PATCH tag' \
  '.draft == false and .prerelease == false' \
  'git merge-base --is-ancestor' \
  'git push origin refs/tags/latest --force' \
  "git ls-remote origin 'refs/tags/latest^{}'"; do
  grep -Fq "$required" "$PROMOTION_WORKFLOW" \
    || fail "promotion workflow is missing: $required"
done

grep -Eq 'uses: actions/checkout@[0-9a-f]{40} # v[0-9]' "$PROMOTION_WORKFLOW" \
  || fail 'promotion checkout must use a reviewed immutable commit SHA'

echo 'Release creation and shared latest promotion are independently gated.'
