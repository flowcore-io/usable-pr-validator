#!/usr/bin/env bash
set -euo pipefail

echo "::group::Testing MCP Connection"

# Check if .mcp.json exists
if [ ! -f ".mcp.json" ]; then
  echo "::error::.mcp.json file not found"
  echo "MCP server configuration is missing"
  exit 1
fi

echo "✅ .mcp.json file found"
echo ""
echo "Configuration:"
# Show config without exposing token
jq '.mcpServers | to_entries[] | {name: .key, command: .value.command, hasToken: (.value.env.USABLE_API_TOKEN != null)}' .mcp.json

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
echo "Testing MCP server startup..."
echo "Current USABLE_API_TOKEN in shell: ${USABLE_API_TOKEN:0:20}..." # Show first 20 chars only

echo ""
echo "Attempting to start MCP server manually with explicit env vars..."

# Test if the MCP server can start WITH explicit environment variables
USABLE_API_TOKEN="$USABLE_API_TOKEN" USABLE_BASE_URL="$USABLE_URL" timeout 5s npx --yes @usabledev/mcp-server@latest server 2>&1 | head -30 &
MCP_PID=$!
sleep 3
if ps -p $MCP_PID > /dev/null 2>&1; then
  echo "✅ MCP server process started successfully (PID: $MCP_PID)"
  kill $MCP_PID 2>/dev/null || true
else
  echo "::warning::MCP server process failed to start or exited quickly"
fi

echo ""
echo "Note: If manual start works but ForgeCode doesn't see MCP tools,"
echo "it means ForgeCode isn't properly passing env vars from .mcp.json"

echo ""
echo "Exporting environment variables for MCP server..."
# ForgeCode doesn't pass env vars from .mcp.json, so we export them globally
export USABLE_API_TOKEN="${USABLE_API_TOKEN}"
export USABLE_BASE_URL="${USABLE_URL}"
echo "✅ USABLE_API_TOKEN exported (${USABLE_API_TOKEN:0:20}...)"
echo "✅ USABLE_BASE_URL exported ($USABLE_BASE_URL)"

echo ""
echo "Checking for MCP server processes before ForgeCode starts..."
ps aux | grep -i "mcp-server\|@usabledev" | grep -v grep || echo "No MCP server processes found"

echo ""
echo "Running ForgeCode with MCP test prompt..."
echo "Current working directory: $(pwd)"
echo ".mcp.json exists in PWD: $([ -f .mcp.json ] && echo 'YES' || echo 'NO')"
echo ""
echo "Capturing both stdout and stderr to see MCP initialization..."

# Run ForgeCode with the test prompt, capturing all output including stderr
# Also enable ForgeCode debug logging to see MCP initialization
RUST_LOG=debug forge -p "$(cat /tmp/mcp-test-prompt.txt)" > /tmp/mcp-test-stdout.txt 2> /tmp/mcp-test-stderr.txt &
FORGE_PID=$!

# Wait a bit longer for MCP initialization and check for processes
sleep 5
echo ""
echo "Checking for MCP server processes while ForgeCode is running..."
ps aux | grep -i "mcp-server\|@usabledev" | grep -v grep || echo "⚠️  No MCP server subprocess found!"

# Check if there are any MCP-related errors in system logs
echo ""
echo "Checking forge stderr for MCP initialization logs..."
if [ -f /tmp/mcp-test-stderr.txt ] && [ -s /tmp/mcp-test-stderr.txt ]; then
  grep -i "mcp\|server\|stdio\|initialize" /tmp/mcp-test-stderr.txt || echo "No MCP-related logs in stderr"
else
  echo "stderr file is empty or doesn't exist yet"
fi

echo ""
echo "Checking for errors in stderr..."
if [ -s /tmp/mcp-test-stderr.txt ]; then
  echo "::group::ForgeCode stderr (may contain MCP initialization errors)"
  cat /tmp/mcp-test-stderr.txt
  echo "::endgroup::"
else
  echo "No errors in stderr"
fi

# Combine stdout and stderr for full output
cat /tmp/mcp-test-stdout.txt /tmp/mcp-test-stderr.txt > /tmp/mcp-test-output.txt 2>&1

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
echo "::group::ForgeCode Debug Logs (stderr - with RUST_LOG=debug)"
if [ -f /tmp/mcp-test-stderr.txt ] && [ -s /tmp/mcp-test-stderr.txt ]; then
  echo "Debug logs (first 300 lines - may show MCP initialization details):"
  head -300 /tmp/mcp-test-stderr.txt
else
  echo "No debug logs captured"
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


