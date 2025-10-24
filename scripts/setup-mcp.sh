#!/usr/bin/env bash
set -euo pipefail

echo "::group::Setting up MCP Server Integration"

# Set defaults for local testing
MCP_SECRET_NAME="${MCP_SECRET_NAME:-USABLE_API_TOKEN}"
MCP_URL="${MCP_SERVER_URL:-https://usable.dev/api/mcp}"

# Get the MCP token from environment using the secret name
MCP_TOKEN="${!MCP_SECRET_NAME:-}"

if [ -z "$MCP_TOKEN" ]; then
  echo "::error::MCP token not found in environment variable: $MCP_SECRET_NAME"
  echo "Please ensure the secret is set in your workflow: env.$MCP_SECRET_NAME"
  echo "For local testing: export USABLE_API_TOKEN='<your-usable-api-token>'"
  exit 1
fi

# Validate MCP URL (should be set by default now)
if [ -z "$MCP_URL" ]; then
  echo "::error::MCP_URL is required when MCP is enabled"
  exit 1
fi

# Create Gemini settings file with MCP configuration
cat > /tmp/gemini-settings.json <<EOF
{
  "mcpServers": {
    "usable": {
      "httpUrl": "$MCP_URL",
      "headers": {
        "Authorization": "Bearer $MCP_TOKEN"
      }
    }
  }
}
EOF

# Set restrictive permissions
chmod 600 /tmp/gemini-settings.json

# Set environment variable for Gemini CLI to use this settings file
export GEMINI_SETTINGS="/tmp/gemini-settings.json"

# Write to GITHUB_ENV for subsequent steps (if in GitHub Actions)
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "GEMINI_SETTINGS=/tmp/gemini-settings.json" >> "$GITHUB_ENV"
fi

echo "✅ MCP server configured"
echo "  URL: $MCP_URL"
echo "  Settings file: /tmp/gemini-settings.json"

# Debug: Show settings file content (mask token)
echo "  Configuration preview:"
cat /tmp/gemini-settings.json | sed 's/"Bearer [^"]*"/"Bearer ***MASKED***"/g' | sed 's/^/    /'

echo "::endgroup::"
