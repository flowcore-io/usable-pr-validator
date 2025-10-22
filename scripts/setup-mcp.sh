#!/usr/bin/env bash
set -euo pipefail

echo "::group::Setting up MCP Server Integration"

# Get the MCP token from environment
# In GitHub Actions: MCP_SECRET_NAME points to the env var name (e.g., USABLE_API_TOKEN)
# In local testing: Just use USABLE_API_TOKEN directly
if [ -n "${MCP_SECRET_NAME:-}" ]; then
  # GitHub Actions mode: indirect reference
  MCP_TOKEN="${!MCP_SECRET_NAME:-}"
else
  # Local testing mode: direct token
  MCP_TOKEN="${USABLE_API_TOKEN:-}"
fi

if [ -z "$MCP_TOKEN" ]; then
  echo "::error::MCP token not found"
  echo "For GitHub Actions: Ensure env.${MCP_SECRET_NAME:-USABLE_API_TOKEN} is set"
  echo "For local testing: Export USABLE_API_TOKEN environment variable"
  exit 1
fi

# Validate MCP URL
if [ -z "$MCP_URL" ]; then
  echo "::error::MCP_URL is required when MCP is enabled"
  exit 1
fi

# Create ForgeCode MCP configuration
# ForgeCode looks for MCP config in forge.yaml or can use environment variables
cat > /tmp/forge-mcp-config.yaml <<EOF
mcp_servers:
  usable:
    http_url: "$MCP_URL"
    headers:
      Authorization: "Bearer $MCP_TOKEN"
EOF

# Set restrictive permissions
chmod 600 /tmp/forge-mcp-config.yaml

# Export as environment variable for forge to pick up
export FORGE_MCP_CONFIG="/tmp/forge-mcp-config.yaml"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "FORGE_MCP_CONFIG=/tmp/forge-mcp-config.yaml" >> "$GITHUB_ENV"
fi

echo "✅ MCP server configured for ForgeCode"
echo "  URL: $MCP_URL"
echo "  Config file: /tmp/forge-mcp-config.yaml"

# Debug: Show settings file content (mask token)
echo "  Configuration preview:"
cat /tmp/forge-mcp-config.yaml | sed 's/Bearer [^"]*$/Bearer ***MASKED***/g' | sed 's/^/    /'

echo "::endgroup::"
