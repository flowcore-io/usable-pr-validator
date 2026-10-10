#!/usr/bin/env bash
set -euo pipefail
umask 077

echo "::group::Setting up MCP Server Integration"

# Set defaults for local testing
MCP_SECRET_NAME="${MCP_SECRET_NAME:-USABLE_API_TOKEN}"
MCP_URL="${MCP_URL:-${MCP_SERVER_URL:-https://usable.dev/api/mcp}}"
PROVIDER="${PROVIDER:-opencode}"
OPENCODE_PROVIDER="${OPENCODE_PROVIDER:-openrouter}"
OPENCODE_MODEL="${OPENCODE_MODEL:-moonshotai/kimi-k2.5}"

# Get the MCP token from environment using the secret name
MCP_TOKEN="${!MCP_SECRET_NAME:-}"

if [ -z "$MCP_TOKEN" ]; then
  echo "::error::MCP token not found in environment variable: $MCP_SECRET_NAME"
  echo "Please ensure the secret is set in your workflow: env.$MCP_SECRET_NAME"
  echo "For local testing: export USABLE_API_TOKEN='<your-usable-api-token>'"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "::error::jq is required but not found. Please install jq or use a GitHub Actions runner with jq pre-installed."
  exit 1
fi

# Validate MCP URL (should be set by default now)
if [ -z "$MCP_URL" ]; then
  echo "::error::MCP_URL is required when MCP is enabled"
  exit 1
fi

if [ "$PROVIDER" = "opencode" ]; then
  # Build JSON with jq so tokens, URLs, and IDs are always escaped correctly.
  # Include fallback as a second enabled provider when configured so opencode
  # can route to it via `-m <fallback-provider>/<fallback-model>` without re-config.
  FALLBACK_OPENCODE_PROVIDER="${FALLBACK_OPENCODE_PROVIDER:-}"
  if [ "$FALLBACK_OPENCODE_PROVIDER" = "$OPENCODE_PROVIDER" ]; then
    FALLBACK_OPENCODE_PROVIDER=""
  fi

  # Restrict any existing config before writing credentials into it.
  touch /tmp/opencode.json
  chmod 600 /tmp/opencode.json
  # Create OpenCode configuration with MCP and provider settings
  jq -n \
    --arg provider "$OPENCODE_PROVIDER" \
    --arg fallback "$FALLBACK_OPENCODE_PROVIDER" \
    --arg model "${OPENCODE_PROVIDER}/${OPENCODE_MODEL}" \
    --arg url "$MCP_URL" \
    --arg auth "Bearer ${MCP_TOKEN}" \
    --arg workspace "${WORKSPACE_ID:-}" \
    '{
      "$schema": "https://opencode.ai/config.json",
      provider: ({($provider): {}} + (if $fallback == "" then {} else {($fallback): {}} end)),
      model: $model,
      autoupdate: false,
      tools: {"usable_get-memory-fragment-content": false},
      mcp: {usable: {
        type: "remote", url: $url, enabled: true,
        headers: {Authorization: $auth, "x-workspace-id": $workspace}
      }}
    }' > /tmp/opencode.json

  # Set restrictive permissions
  chmod 600 /tmp/opencode.json

  # Copy to repo root so opencode can find it (opencode reads from cwd)
  touch ./opencode.json
  chmod 600 ./opencode.json
  cp /tmp/opencode.json ./opencode.json
  chmod 600 ./opencode.json

  echo "✅ OpenCode MCP server configured"
  echo "  Model: ${OPENCODE_PROVIDER}/${OPENCODE_MODEL}"
  if [ -n "$FALLBACK_OPENCODE_PROVIDER" ] && [ "$FALLBACK_OPENCODE_PROVIDER" != "$OPENCODE_PROVIDER" ]; then
    echo "  Fallback provider enabled: ${FALLBACK_OPENCODE_PROVIDER}"
  fi
  echo "  Settings file: ./opencode.json"

else
  # Create Gemini settings file with MCP configuration
  touch /tmp/gemini-settings.json
  chmod 600 /tmp/gemini-settings.json
  jq -n \
    --arg url "$MCP_URL" \
    --arg auth "Bearer ${MCP_TOKEN}" \
    --arg workspace "${WORKSPACE_ID:-}" \
    '{mcpServers: {usable: {
      httpUrl: $url,
      excludeTools: ["get-memory-fragment-content"],
      headers: {Authorization: $auth, "x-workspace-id": $workspace}
    }}}' > /tmp/gemini-settings.json

  # Set restrictive permissions
  chmod 600 /tmp/gemini-settings.json

  # Gemini CLI 0.7.0 reads this documented system-settings override. The old
  # GEMINI_SETTINGS variable is not consumed by that pinned CLI version.
  export GEMINI_CLI_SYSTEM_SETTINGS_PATH="/tmp/gemini-settings.json"

  # Write to GITHUB_ENV for subsequent steps (if in GitHub Actions)
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "GEMINI_CLI_SYSTEM_SETTINGS_PATH=/tmp/gemini-settings.json" >> "$GITHUB_ENV"
  fi

  echo "✅ Gemini MCP server configured"
  echo "  Settings file: /tmp/gemini-settings.json"

fi

echo "::endgroup::"
