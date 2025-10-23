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

echo "Usable URL: $USABLE_URL"

# Register MCP server with ForgeCode using stdio transport via npx
echo ""
echo "Registering MCP server with ForgeCode..."

# Build the server configuration JSON
SERVER_CONFIG=$(cat <<EOF
{
  "command": "npx",
  "args": ["@usabledev/mcp-server@latest", "server"],
  "env": {
    "USABLE_API_TOKEN": "${USABLE_API_TOKEN}",
    "USABLE_BASE_URL": "${USABLE_URL}"
  }
}
EOF
)

echo "  Type: stdio transport via npx"
echo "  Command: npx @usabledev/mcp-server@latest server"
echo "  Base URL: ${USABLE_URL}"
echo ""

# Remove existing server if it exists (to avoid conflicts)
forge mcp remove usable-local 2>/dev/null || true

# Register the server
if forge mcp add-json usable-local "$SERVER_CONFIG" --scope local 2>&1; then
  echo "✅ MCP server 'usable-local' registered successfully"
  echo ""
  echo "Verifying registration..."
  forge mcp list 2>&1 | grep -i "usable-local" || echo "⚠️ Server registered but not shown in list"
else
  echo "::error::Failed to register MCP server with ForgeCode"
  exit 1
fi

echo "::endgroup::"
