#!/usr/bin/env bash
set -euo pipefail

echo "::group::Preparing Prompts for Validation"

# Verify jq is available (pre-installed on GitHub Actions runners)
if ! command -v jq &> /dev/null; then
  echo "::error::jq is required but not found. Please install jq or use a GitHub Actions runner with jq pre-installed."
  exit 1
fi

# Get USABLE_API_TOKEN from secrets
USABLE_API_TOKEN="${!MCP_SECRET_NAME:-}"
if [ -z "$USABLE_API_TOKEN" ]; then
  echo "::warning::USABLE_API_TOKEN not found. Skipping MCP system prompt fetching."
  HAS_API_TOKEN=false
else
  HAS_API_TOKEN=true
fi

USABLE_API_BASE="https://usable.dev/api"
HARDCODED_SYSTEM_PROMPT="${ACTION_PATH}/system-prompt.md"
MCP_SYSTEM_PROMPT_FILE="/tmp/mcp-system-prompt.md"
USER_PROMPT_FILE="/tmp/user-prompt.md"
FINAL_PROMPT_FILE="/tmp/dynamic-prompt.md"

# Function to fetch fragment content by ID
fetch_fragment_content() {
  local fragment_id="$1"
  
  echo "Fetching fragment content: $fragment_id"
  
  local fetch_url="${USABLE_API_BASE}/v1/fragments/${fragment_id}"
  
  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$fetch_url" \
    -H "Authorization: Bearer $USABLE_API_TOKEN")
  
  local http_code
  http_code=$(echo "$response" | tail -n1)
  local body
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" != "200" ]; then
    echo "::error::Failed to fetch fragment content (HTTP $http_code)"
    echo "Response: $body"
    return 1
  fi
  
  # Use jq to parse JSON and extract content field
  # Note: jq is pre-installed on GitHub Actions runners
  local content
  content=$(echo "$body" | jq -r '.content // empty' 2>&1)
  
  if [ $? -ne 0 ]; then
    echo "::error::Failed to parse fragment JSON response"
    echo "Error: $content"
    return 1
  fi
  
  if [ -z "$content" ]; then
    echo "::error::Fragment content is empty"
    return 1
  fi
  
  echo "$content"
}

# Function to fetch MCP system prompt
fetch_mcp_system_prompt() {
  local workspace_id="$1"
  
  echo "Fetching MCP system prompt for workspace: $workspace_id"
  
  local fetch_url="${USABLE_API_BASE}/workspaces/${workspace_id}/mcp-system-prompt"
  
  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$fetch_url" \
    -H "Authorization: Bearer $USABLE_API_TOKEN")
  
  local http_code
  http_code=$(echo "$response" | tail -n1)
  local body
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" != "200" ]; then
    echo "::warning::Failed to fetch MCP system prompt (HTTP $http_code), continuing without it"
    return 1
  fi
  
  # The API might return JSON with a content field, or plain text
  # Try to parse as JSON first using jq
  # Note: jq is pre-installed on GitHub Actions runners
  local content
  content=$(echo "$body" | jq -r '.content // .prompt // empty' 2>/dev/null)
  
  # If JSON parsing returned empty, use the body as-is (assuming plain text)
  if [ -z "$content" ]; then
    content="$body"
  fi
  
  # Verify content is not empty after parsing
  if [ -z "$content" ]; then
    echo "::warning::MCP system prompt content is empty after parsing."
    return 1
  fi
  
  echo "$content"
}

# Main execution
main() {
  local has_hardcoded_system=false
  local has_mcp_system=false
  local has_user_prompt=false
  
  # Step 1: Load hardcoded system prompt from action
  if [ -f "$HARDCODED_SYSTEM_PROMPT" ]; then
    echo "✅ Loading hardcoded system prompt from action"
    has_hardcoded_system=true
    echo "Size: $(wc -c < "$HARDCODED_SYSTEM_PROMPT") bytes"
  else
    echo "::warning::Hardcoded system prompt not found at: $HARDCODED_SYSTEM_PROMPT"
  fi
  
  # Step 2: Fetch MCP system prompt from Usable API
  if [ "$HAS_API_TOKEN" = true ] && [ -n "$WORKSPACE_ID" ]; then
    local mcp_content
    mcp_content=$(fetch_mcp_system_prompt "$WORKSPACE_ID")
    
    if [ -n "$mcp_content" ]; then
      echo "$mcp_content" > "$MCP_SYSTEM_PROMPT_FILE"
      has_mcp_system=true
      echo "✅ MCP system prompt fetched successfully"
      echo "Size: $(wc -c < "$MCP_SYSTEM_PROMPT_FILE") bytes"
    fi
  else
    echo "Skipping MCP system prompt (no API token or workspace ID)"
  fi
  
  # Step 3: Determine user prompt source
  if [ "$USE_DYNAMIC_PROMPTS" = "true" ]; then
    # Dynamic prompts - fetch from Usable API
    if [ -z "$PROMPT_FRAGMENT_ID" ]; then
      echo "::error::prompt-fragment-id is required when use-dynamic-prompts is enabled. Provide a valid Usable fragment UUID (e.g., 'a859c565-ddb9-4d3e-b716-4b644b08e161')"
      exit 1
    fi
    
    if [ "$HAS_API_TOKEN" = false ]; then
      echo "::error::USABLE_API_TOKEN required for dynamic prompts"
      exit 1
    fi
    
    echo "Fetching user prompt from fragment: $PROMPT_FRAGMENT_ID"
    
    local user_content
    user_content=$(fetch_fragment_content "$PROMPT_FRAGMENT_ID")
    
    if [ -n "$user_content" ]; then
      echo "$user_content" > "$USER_PROMPT_FILE"
      has_user_prompt=true
      echo "✅ User prompt fetched successfully"
      echo "Size: $(wc -c < "$USER_PROMPT_FILE") bytes"
    else
      echo "::error::Failed to fetch user prompt"
      exit 1
    fi
  else
    # Static prompt file
    if [ -n "$CUSTOM_PROMPT_FILE" ] && [ -f "$CUSTOM_PROMPT_FILE" ]; then
      echo "Using static prompt file: $CUSTOM_PROMPT_FILE"
      cp "$CUSTOM_PROMPT_FILE" "$USER_PROMPT_FILE"
      has_user_prompt=true
      echo "✅ Static prompt loaded"
      echo "Size: $(wc -c < "$USER_PROMPT_FILE") bytes"
    else
      echo "::error::No user prompt file provided or file not found"
      exit 1
    fi
  fi
  
  # Step 4: Merge prompts in order: hardcoded system → MCP system → user prompt
  echo "Merging prompts..."
  
  {
    if [ "$has_hardcoded_system" = true ]; then
      cat "$HARDCODED_SYSTEM_PROMPT"
      echo ""
      echo "---"
      echo ""
    fi
    
    if [ "$has_mcp_system" = true ]; then
      cat "$MCP_SYSTEM_PROMPT_FILE"
      echo ""
      echo "---"
      echo ""
    fi
    
    if [ "$has_user_prompt" = true ]; then
      cat "$USER_PROMPT_FILE"
    fi
  } > "$FINAL_PROMPT_FILE"
  
  echo "✅ Prompts merged successfully"
  echo "Final prompt size: $(wc -c < "$FINAL_PROMPT_FILE") bytes"
  echo "Final prompt lines: $(wc -l < "$FINAL_PROMPT_FILE") lines"
  
  # Display preview (first 50 lines)
  echo "::group::Final Prompt Preview (first 50 lines)"
  head -50 "$FINAL_PROMPT_FILE" || true
  echo "::endgroup::"
  
  echo "::endgroup::"
}

# Run main function
main
