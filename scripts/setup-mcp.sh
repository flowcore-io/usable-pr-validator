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

# Remove any existing usable MCP server first (to avoid duplicates)
forge mcp remove usable 2>/dev/null || echo "  No existing usable server to remove"

# Add Usable MCP server using the official @usabledev/mcp-server package
# This uses stdio transport and handles authentication via environment variables
echo "Adding Usable MCP server to ForgeCode..."
forge mcp add usable "npx" \
  --transport stdio \
  --scope local \
  --args "@usabledev/mcp-server@latest" \
  --args "server" \
  --env "USABLE_API_TOKEN=$MCP_TOKEN" \
  --env "USABLE_BASE_URL=$MCP_URL" 2>&1

echo "✅ MCP server configured for ForgeCode"
echo "  Package: @usabledev/mcp-server@latest"
echo "  Base URL: $MCP_URL"

# List configured servers for verification
echo "  Configured MCP servers:"
forge mcp list 2>&1 | sed 's/^/    /' || echo "    (Unable to list servers)"

echo "::endgroup::"
