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

# Install @usabledev/mcp-server globally for faster startup
echo ""
echo "Installing @usabledev/mcp-server globally..."
npm install -g @usabledev/mcp-server@latest 2>&1 | grep -E "added|up to date|@usabledev" || echo "  Installation output suppressed"
echo "✅ MCP server package installed"

# Write .mcp.json file in the working directory with authentication
# ForgeCode loads MCP servers from .mcp.json in the current directory
echo ""
echo "Writing .mcp.json configuration..."

# Create the .mcp.json file with the Usable MCP server configuration
# Using stdio transport via @usabledev/mcp-server package
cat > .mcp.json <<EOF
{
  "mcpServers": {
    "usable": {
      "command": "npx",
      "args": ["@usabledev/mcp-server@latest", "server"],
      "env": {
        "USABLE_API_TOKEN": "$USABLE_API_TOKEN",
        "USABLE_BASE_URL": "$USABLE_URL"
      }
    }
  }
}
EOF

echo "✅ MCP server configured in .mcp.json"
echo "  Type: stdio (via @usabledev/mcp-server)"
echo "  Command: npx @usabledev/mcp-server@latest server"
echo "  Auth: Via USABLE_API_TOKEN environment variable"

# Verify the configuration
if [ -f ".mcp.json" ]; then
  echo "  Configuration file created successfully"
  echo "  MCP server 'usable' will be available to ForgeCode"
  
  # Show config (without exposing token)
  if command -v jq &> /dev/null; then
    echo ""
    echo "  Configuration preview:"
    jq '.mcpServers | to_entries[] | {name: .key, command: .value.command, args: .value.args, hasToken: (.value.env.USABLE_API_TOKEN != null)}' .mcp.json 2>/dev/null | sed 's/^/    /' || echo "    (Preview unavailable)"
  fi
  
  echo ""
  echo "  Full .mcp.json content (with token masked):"
  cat .mcp.json | sed "s/$USABLE_API_TOKEN/***MASKED***/g" | sed 's/^/    /' || echo "    (Could not read file)"
else
  echo "::error::Failed to create .mcp.json"
  exit 1
fi

echo "::endgroup::"
