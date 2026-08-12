#!/usr/bin/env bash
set -euo pipefail

OPENCODE_PROVIDER="${OPENCODE_PROVIDER:-openrouter}"
OPENCODE_VERSION="${OPENCODE_VERSION:-1.18.17}"

echo "::group::Setting up OpenCode CLI + ${OPENCODE_PROVIDER}"

# Get the secret value from the environment using the secret name
SECRET_NAME="${OPENCODE_SECRET_NAME:-OPENCODE_API_KEY}"
SECRET_VALUE="${!SECRET_NAME:-}"

if [ -z "$SECRET_VALUE" ]; then
  echo "::error::API key not found in environment variable: $SECRET_NAME"
  echo "Please ensure the secret is set in your workflow: env.$SECRET_NAME"
  exit 1
fi

# Install an exact OpenCode version through npm. The previous remote install
# script downloaded a release archive without verifying its content, so a CDN
# error page could be piped into tar and fail with "not in gzip format".
installed_version=""
if command -v opencode &> /dev/null; then
  installed_version="$(opencode --version 2>/dev/null || true)"
  installed_version="${installed_version#v}"
fi

if [ "$installed_version" != "$OPENCODE_VERSION" ]; then
  echo "Installing OpenCode CLI ${OPENCODE_VERSION} with npm..."
  npm install --global --no-audit --no-fund "opencode-ai@${OPENCODE_VERSION}"
fi

if ! command -v opencode &> /dev/null; then
  echo "::error::OpenCode CLI installation failed - command not found after npm install"
  echo "PATH: $PATH"
  exit 1
fi

installed_version="$(opencode --version 2>/dev/null || true)"
installed_version="${installed_version#v}"
if [ "$installed_version" != "$OPENCODE_VERSION" ]; then
  echo "::error::OpenCode CLI version mismatch: expected ${OPENCODE_VERSION}, got ${installed_version:-unknown}"
  exit 1
fi

echo "✅ OpenCode CLI installed: ${installed_version}"

# Determine the correct env var name for the provider
# OpenCode expects provider-specific env vars (e.g., OPENROUTER_API_KEY, ANTHROPIC_API_KEY)
PROVIDER_ENV_VAR="$(echo "${OPENCODE_PROVIDER}" | tr '[:lower:]' '[:upper:]')_API_KEY"

export "$PROVIDER_ENV_VAR"="$SECRET_VALUE"

# Write to GITHUB_ENV for subsequent steps (if in GitHub Actions)
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "$PROVIDER_ENV_VAR=$SECRET_VALUE" >> "$GITHUB_ENV"
fi

echo "✅ ${OPENCODE_PROVIDER} authentication configured (${PROVIDER_ENV_VAR})"
echo "::endgroup::"
