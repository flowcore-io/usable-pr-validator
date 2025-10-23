#!/usr/bin/env bash
set -euo pipefail

# Test if the MCP server responds to MCP protocol requests over stdio

echo "Testing MCP server stdio protocol..."
echo ""

# Export environment variables
export USABLE_API_TOKEN="${USABLE_API_TOKEN}"
export USABLE_BASE_URL="${USABLE_URL:-https://usable.dev}"

echo "Starting MCP server and sending initialize request..."
echo ""

# Send an MCP initialize request via stdin
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | \
  npx --yes @usabledev/mcp-server@latest server 2>&1 | head -50

echo ""
echo "If you see a valid JSON-RPC response above with server info, the MCP server works."
echo "If you see errors or no response, the MCP server has issues."

