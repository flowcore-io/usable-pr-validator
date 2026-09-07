#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  set -- scripts .github
fi

matches=$(
  grep -R -I -n -E \
    --include='*.sh' \
    --include='*.yml' \
    --include='*.yaml' \
    --exclude='check-no-hardcoded-secrets.sh' \
    --exclude='test-secret-policy.sh' \
    -- 'AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|^[[:space:]]*(password|secret|token):[[:space:]]*[A-Za-z0-9+/=._-]{16,}[[:space:]]*$' \
    "$@" || true
)

if [ -n "$matches" ]; then
  echo 'Potential hardcoded credential material found:' >&2
  echo "$matches" >&2
  exit 1
fi

echo 'No hardcoded credential material found.'
