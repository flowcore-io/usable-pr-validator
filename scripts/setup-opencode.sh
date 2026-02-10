#!/usr/bin/env bash
set -euo pipefail

echo "::group::Setting up OpenCode CLI + OpenRouter"

# Get the secret value from the environment using the secret name
SECRET_NAME="${OPENROUTER_SECRET_NAME:-OPENROUTER_API_KEY}"
SECRET_VALUE="${!SECRET_NAME:-}"

if [ -z "$SECRET_VALUE" ]; then
  echo "::error::OpenRouter API key not found in environment variable: $SECRET_NAME"
  echo "Please ensure the secret is set in your workflow: env.$SECRET_NAME"
  echo "For local testing: export OPENROUTER_API_KEY='<your-openrouter-api-key>'"
  exit 1
fi

# Install OpenCode CLI
echo "Installing OpenCode CLI..."
if ! command -v opencode &> /dev/null; then
  curl -fsSL https://raw.githubusercontent.com/opencode-ai/opencode/refs/heads/main/install | bash

  # The installer puts opencode in ~/.opencode/bin and updates .bashrc,
  # but PATH changes from .bashrc don't apply to the current shell.
  # Add known install locations to PATH for this session.
  for dir in "$HOME/.opencode/bin" "$HOME/.local/bin"; do
    if [ -f "$dir/opencode" ]; then
      export PATH="$dir:$PATH"
      # Also ensure subsequent steps have it (installer may already do this for GITHUB_PATH)
      if [ -n "${GITHUB_PATH:-}" ]; then
        echo "$dir" >> "$GITHUB_PATH"
      fi
      break
    fi
  done

  if ! command -v opencode &> /dev/null; then
    echo "::error::OpenCode CLI installation failed - command not found after install"
    echo "Searched: ~/.opencode/bin, ~/.local/bin"
    echo "PATH: $PATH"
    exit 1
  fi
fi

echo "✅ OpenCode CLI installed: $(opencode --version 2>/dev/null || echo 'version unknown')"

# Export OpenRouter API key for OpenCode to use
export OPENROUTER_API_KEY="$SECRET_VALUE"

# Write to GITHUB_ENV for subsequent steps (if in GitHub Actions)
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "OPENROUTER_API_KEY=$SECRET_VALUE" >> "$GITHUB_ENV"
fi

echo "✅ OpenRouter authentication configured"
echo "::endgroup::"
