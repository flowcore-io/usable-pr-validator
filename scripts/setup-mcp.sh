#!/usr/bin/env bash
set -euo pipefail

echo "::group::Setting up MCP Server Integration"

# Get the Usable API token from environment
if [ -z "${USABLE_API_TOKEN:-}" ]; then
  echo "::error::USABLE_API_TOKEN not found"
  echo "Please set USABLE_API_TOKEN environment variable or secret"
  exit 1
fi

# Get Usable URL from environment (default to usable.dev)
USABLE_URL="${USABLE_URL:-https://usable.dev}"
MCP_ENDPOINT="${USABLE_URL}/api/mcp"

echo "Usable URL: $USABLE_URL"
echo "MCP Endpoint: $MCP_ENDPOINT"

# Write .mcp.json file in the working directory with authentication
# ForgeCode loads MCP servers from .mcp.json in the current directory
echo "Writing .mcp.json configuration..."

# Create the .mcp.json file with the Usable MCP server configuration
cat > .mcp.json <<EOF
{
  "mcpServers": {
    "usable": {
      "url": "$MCP_ENDPOINT",
      "headers": {
        "Authorization": "Bearer $USABLE_API_TOKEN"
      }
    }
  }
}
EOF

echo "✅ MCP server configured in .mcp.json"
echo "  Endpoint: $MCP_ENDPOINT"
echo "  Auth: Bearer token (configured)"

# Verify the configuration
if [ -f ".mcp.json" ]; then
  echo "  Configuration file created successfully"
  echo "  MCP server 'usable' will be available to ForgeCode"
else
  echo "::error::Failed to create .mcp.json"
  exit 1
fi

echo "::endgroup::"
