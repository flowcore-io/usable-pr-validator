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

# Remove any existing usable MCP server first (to avoid duplicates)
forge mcp remove usable 2>/dev/null || echo "  No existing usable server to remove"

# Add Usable MCP server using HTTP transport with Authorization header
# ForgeCode requires JSON configuration to pass HTTP headers
echo "Adding Usable MCP server to ForgeCode..."
echo "  Endpoint: $MCP_ENDPOINT"
echo "  Auth: Bearer token (configured)"

# Use forge mcp add-json to configure HTTP transport with Authorization header
forge mcp add-json "usable" "{\"url\":\"$MCP_ENDPOINT\",\"headers\":{\"Authorization\":\"Bearer $USABLE_API_TOKEN\"}}" 2>&1

echo "✅ MCP server configured for ForgeCode"
echo "  Transport: HTTP with Authorization header"
echo "  Endpoint: $MCP_ENDPOINT"

# List configured servers for verification
echo "  Configured MCP servers:"
forge mcp list 2>&1 | sed 's/^/    /' || echo "    (Unable to list servers)"

echo "::endgroup::"
