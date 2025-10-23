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

# Write .mcp.json file with HTTP transport (more reliable in CI than stdio)
# ForgeCode loads MCP servers from .mcp.json in the current directory
echo ""
echo "Writing .mcp.json configuration..."

# Create the .mcp.json file with HTTP transport to Usable's MCP endpoint
# This avoids stdio buffering issues in GitHub Actions CI
cat > .mcp.json <<EOF
{
  "mcpServers": {
    "usable": {
      "url": "${USABLE_URL}/api/mcp",
      "transport": "http",
      "headers": {
        "Authorization": "Bearer ${USABLE_API_TOKEN}",
        "Content-Type": "application/json"
      }
    }
  }
}
EOF

echo "✅ MCP server configured in .mcp.json"
echo "  Type: HTTP transport (avoids stdio issues in CI)"
echo "  URL: ${USABLE_URL}/api/mcp"
echo "  Auth: Via Authorization header"

# Verify the configuration
if [ -f ".mcp.json" ]; then
  echo "  Configuration file created successfully"
  echo "  MCP server 'usable' will be available to ForgeCode"
  
  # Show config (without exposing token)
  if command -v jq &> /dev/null; then
    echo ""
    echo "  Configuration preview:"
    jq '.mcpServers | to_entries[] | {name: .key, transport: .value.transport, url: .value.url, hasAuth: (.value.headers.Authorization != null)}' .mcp.json 2>/dev/null | sed 's/^/    /' || echo "    (Preview unavailable)"
  fi
  
  echo ""
  echo "  Full .mcp.json content (with token masked):"
  cat .mcp.json | sed "s/$USABLE_API_TOKEN/***MASKED***/g" | sed 's/^/    /' || echo "    (Could not read file)"
else
  echo "::error::Failed to create .mcp.json"
  exit 1
fi

echo "::endgroup::"
