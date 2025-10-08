#!/usr/bin/env bash
set -euo pipefail

echo "::group::Setting up MCP Server Integration"

# Get the MCP token from environment using the secret name
MCP_TOKEN="${!MCP_SECRET_NAME:-}"

if [ -z "$MCP_TOKEN" ]; then
  echo "::error::MCP token not found in environment variable: $MCP_SECRET_NAME"
  echo "Please ensure the secret is set in your workflow: env.$MCP_SECRET_NAME"
  exit 1
fi

# Validate MCP URL
if [ -z "$MCP_URL" ]; then
  echo "::error::MCP_URL is required when MCP is enabled"
  exit 1
fi

# Create Gemini settings file with MCP configuration
cat > /tmp/gemini-settings.json <<EOF
{
  "mcpServers": {
    "knowledge-base": {
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
echo "GEMINI_SETTINGS=/tmp/gemini-settings.json" >> $GITHUB_ENV

echo "✅ MCP server configured"
echo "  URL: $MCP_URL"
echo "::endgroup::"
