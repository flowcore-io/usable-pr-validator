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

# Write .mcp.json file with stdio transport using npx
# ForgeCode loads MCP servers from .mcp.json in the current directory
echo ""
echo "Writing .mcp.json configuration..."

# Create the .mcp.json file with stdio transport using npx
# This uses the Usable MCP server package via npx for better subprocess control
cat > .mcp.json <<EOF
{
  "mcpServers": {
    "usable-local": {
      "command": "npx",
      "args": ["@usabledev/mcp-server@latest", "server"],
      "env": {
        "USABLE_API_TOKEN": "${USABLE_API_TOKEN}",
        "USABLE_BASE_URL": "${USABLE_URL}"
      }
    }
  }
}
EOF

echo "✅ MCP server configured in .mcp.json"
echo "  Type: stdio transport via npx"
echo "  Command: npx @usabledev/mcp-server@latest server"
echo "  Base URL: ${USABLE_URL}"

# Verify the configuration
if [ -f ".mcp.json" ]; then
  echo "  Configuration file created successfully"
  
  # Show config (without exposing token)
  if command -v jq &> /dev/null; then
    echo ""
    echo "  Configuration preview:"
    jq '.mcpServers | to_entries[] | {name: .key, command: .value.command, args: .value.args, hasAuth: (.value.env.USABLE_API_TOKEN != null)}' .mcp.json 2>/dev/null | sed 's/^/    /' || echo "    (Preview unavailable)"
  fi
  
  echo ""
  echo "  Full .mcp.json content (with token masked):"
  cat .mcp.json | sed "s/$USABLE_API_TOKEN/***MASKED***/g" | sed 's/^/    /' || echo "    (Could not read file)"
  
  # Register the MCP server explicitly with ForgeCode
  echo ""
  echo "  Registering MCP server with ForgeCode..."
  SERVER_CONFIG=$(jq -c '.mcpServers["usable-local"]' .mcp.json)
  if forge mcp add-json usable-local "$SERVER_CONFIG" --scope local 2>&1; then
    echo "  ✅ MCP server 'usable-local' registered successfully"
  else
    echo "  ⚠️ MCP server registration returned an error (it may already be registered from .mcp.json)"
  fi
else
  echo "::error::Failed to create .mcp.json"
  exit 1
fi

echo "::endgroup::"
