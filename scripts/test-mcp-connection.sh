#!/usr/bin/env bash
set -euo pipefail

echo "::group::Testing MCP Connection"

# Check if MCP server is registered with ForgeCode
echo "Checking registered MCP servers..."
if ! forge mcp list 2>&1 | grep -q "usable"; then
  echo "::error::MCP server 'usable' not found in ForgeCode configuration"
  echo "Available servers:"
  forge mcp list 2>&1 || echo "  (none)"
  echo ""
  echo "Please run setup-mcp.sh first to register the MCP server"
  exit 1
fi

echo "✅ MCP server 'usable' is registered"
echo ""
echo "Configuration:"
forge mcp get usable 2>&1 || echo "  (Unable to retrieve configuration)"

echo ""
echo "Creating MCP test prompt..."

# Setup provider configuration first (same as validate.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo ""
echo "Setting up provider configuration..."
if [ -f "$SCRIPT_DIR/setup-provider.sh" ]; then
  source "$SCRIPT_DIR/setup-provider.sh" || {
    echo "::error::Failed to setup provider"
    exit 1
  }
else
  echo "::warning::setup-provider.sh not found, skipping provider setup"
fi

echo ""

# Set ForgeCode model configuration (prevents interactive prompt)
if [ -n "${MODEL:-}" ]; then
  echo "Configuring ForgeCode model: ${MODEL}"
  forge config set --model "${MODEL}" 2>&1 || echo "::warning::Could not set model config"
else
  echo "::warning::MODEL not set, ForgeCode may prompt for model selection"
fi

echo ""
# Create a simple test prompt that lists available tools
cat > /tmp/mcp-test-prompt.txt <<'EOF'
# MCP Connection Test

Your task is to verify the MCP connection by listing your available tools.

## Instructions

1. List ALL available tools you have access to
2. Look for tools that start with `mcp_usable_` prefix
3. If you find MCP tools, call `mcp_usable_list-workspaces` with parameter `{"includeArchived": false}`
4. Report the results

## Output Format

Write your findings to `/tmp/mcp-test-result.json` in this format:

```json
{
  "mcpToolsFound": true/false,
  "toolCount": 0,
  "mcpTools": ["list", "of", "mcp", "tools"],
  "workspacesResult": {
    "success": true/false,
    "workspaces": [],
    "error": "error message if failed"
  }
}
```

IMPORTANT: You must write the JSON file even if no MCP tools are found.
EOF

echo ""
echo "Checking if ForgeCode can see MCP servers in config..."
forge mcp list 2>&1 || echo "⚠️  forge mcp list command not available or failed"

echo ""
echo "🔄 Refreshing MCP cache..."
set +e
CACHE_OUTPUT=$(timeout 30 forge mcp cache refresh 2>&1)
CACHE_EXIT=$?
set -e

if [ $CACHE_EXIT -eq 0 ]; then
  echo "✅ MCP cache refreshed successfully"
elif [ $CACHE_EXIT -eq 124 ]; then
  echo "⚠️ MCP cache refresh timed out after 30 seconds (continuing anyway)"
elif echo "$CACHE_OUTPUT" | grep -q "No such file or directory"; then
  echo "⚠️ No cache directory exists yet (first run) - skipping cache refresh"
else
  echo "⚠️ MCP cache refresh failed - continuing anyway"
  echo "   Error: $(echo "$CACHE_OUTPUT" | grep -i "error" | head -1)"
fi

echo ""
echo "Note: Using stdio transport via npx @usabledev/mcp-server"
echo "  Direct subprocess communication for better control"
echo "  Authentication passed via USABLE_API_TOKEN environment variable"

echo ""
echo "Running ForgeCode with MCP test prompt..."
echo "Current working directory: $(pwd)"
echo ""
echo "Capturing both stdout and stderr to see MCP initialization..."

# Run ForgeCode with the test prompt, capturing all output including stderr
# Use --verbose flag for detailed output
echo "Running ForgeCode with --verbose flag..."
echo "Waiting 5 seconds before starting ForgeCode to ensure MCP server registration is settled..."
sleep 5
forge --verbose -p "$(cat /tmp/mcp-test-prompt.txt)" 2>&1 | tee /tmp/mcp-test-output.txt &
FORGE_PID=$!

# Wait for ForgeCode to initialize and connect to MCP server via stdio
echo "Waiting for ForgeCode to initialize MCP stdio connection..."
sleep 5

# Check for any MCP-related patterns in the output
echo ""
echo "Checking for MCP-related logs in output..."
if [ -f /tmp/mcp-test-output.txt ] && [ -s /tmp/mcp-test-output.txt ]; then
  if grep -qi "mcp\|server\|http\|initialize\|connect" /tmp/mcp-test-output.txt; then
    echo "::group::MCP-related logs found"
    grep -i "mcp\|server\|http\|initialize\|connect" /tmp/mcp-test-output.txt | head -50
    echo "::endgroup::"
  else
    echo "No MCP-related patterns found in output"
  fi
else
  echo "Output file is empty or doesn't exist yet"
fi

# Wait for ForgeCode to complete
if wait $FORGE_PID; then
  echo ""
  echo "ForgeCode execution completed"
else
  echo ""
  echo "::warning::ForgeCode execution had errors"
fi

echo ""
echo "::group::ForgeCode Output"
if [ -f /tmp/mcp-test-output.txt ]; then
  echo "Combined output (first 100 lines):"
  head -100 /tmp/mcp-test-output.txt
else
  echo "No output captured"
fi
echo "::endgroup::"

echo ""
echo "::group::ForgeCode Verbose Output (with --verbose flag)"
if [ -f /tmp/mcp-test-output.txt ] && [ -s /tmp/mcp-test-output.txt ]; then
  echo "Verbose output (first 300 lines - may show MCP initialization details):"
  tail -n +2 /tmp/mcp-test-output.txt | head -300  # Skip first line (duplicate)
else
  echo "No verbose output captured"
fi
echo "::endgroup::"

# Check if result file was created
if [ -f "/tmp/mcp-test-result.json" ]; then
  echo ""
  echo "::group::MCP Test Results"
  cat /tmp/mcp-test-result.json
  echo ""
  echo "::endgroup::"
  
  # Parse results
  if jq -e '.mcpToolsFound == true' /tmp/mcp-test-result.json > /dev/null 2>&1; then
    echo "✅ MCP tools are available to the AI model"
    
    # Check workspace test
    if jq -e '.workspacesResult.success == true' /tmp/mcp-test-result.json > /dev/null 2>&1; then
      WORKSPACE_COUNT=$(jq -r '.workspacesResult.workspaces | length' /tmp/mcp-test-result.json)
      echo "✅ MCP connection successful - found $WORKSPACE_COUNT workspace(s)"
      
      # List workspaces
      echo ""
      echo "Workspaces:"
      jq -r '.workspacesResult.workspaces[] | "  - \(.name) (ID: \(.id))"' /tmp/mcp-test-result.json || echo "  (Unable to parse workspace list)"
      
      echo "::endgroup::"
      exit 0
    else
      echo "❌ MCP tools found but workspace query failed"
      jq -r '.workspacesResult.error // "Unknown error"' /tmp/mcp-test-result.json
      echo "::endgroup::"
      exit 1
    fi
  else
    echo "❌ MCP tools NOT available to the AI model"
    echo ""
    echo "Available tools:"
    jq -r '.mcpTools[]' /tmp/mcp-test-result.json || echo "  (No tools information)"
    echo "::endgroup::"
    exit 1
  fi
else
  echo ""
  echo "::warning::AI model did not create result file"
  echo "This likely means the model couldn't understand the prompt or write the file"
  echo ""
  echo "Checking output for MCP tool mentions..."
  
  if grep -q "mcp_usable" /tmp/mcp-test-output.txt; then
    echo "✅ Found references to mcp_usable tools in output"
  else
    echo "❌ No references to mcp_usable tools found"
    echo "::error::MCP tools are NOT available to the AI model"
  fi
  
  echo "::endgroup::"
  exit 1
fi


