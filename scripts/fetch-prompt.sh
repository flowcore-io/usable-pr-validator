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
PROMPT_OUTPUT_DIR="${PROMPT_OUTPUT_DIR:-/tmp}"
MCP_SYSTEM_PROMPT_FILE="${PROMPT_OUTPUT_DIR}/mcp-system-prompt.md"
USER_PROMPT_FILE="${PROMPT_OUTPUT_DIR}/user-prompt.md"
FINAL_PROMPT_FILE="${PROMPT_OUTPUT_DIR}/dynamic-prompt.md"

# Function to fetch fragment content by ID
fetch_fragment_content() {
  local fragment_id="$1"
  
  echo "Fetching fragment content: $fragment_id" >&2
  
  local fetch_url="${USABLE_API_BASE}/memory-fragments/${fragment_id}"
  
  local response
  if ! response=$(curl -sS -w "\n%{http_code}" \
    -X GET "$fetch_url" \
    -H "Authorization: Bearer $USABLE_API_TOKEN"); then
    echo "::error::Failed to fetch fragment content" >&2
    return 1
  fi
  
  local http_code
  http_code=$(echo "$response" | tail -n1)
  local body
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" != "200" ]; then
    echo "::error::Failed to fetch fragment content (HTTP $http_code)" >&2
    return 1
  fi
  
  # Use jq to parse JSON and extract content field
  # Note: jq is pre-installed on GitHub Actions runners
  local content
  if ! content=$(echo "$body" | jq -er 'select(.success == true) | .fragment.content | select(type == "string" and length > 0)' 2>/dev/null); then
    echo "::error::Failed to parse fragment JSON response" >&2
    return 1
  fi
  
  if [ -z "$content" ]; then
    echo "::error::Fragment content is empty" >&2
    return 1
  fi
  
  echo "$content"
}

# Function to fetch MCP system prompt
fetch_mcp_system_prompt() {
  local workspace_id="$1"
  
  echo "Fetching MCP system prompt for workspace: $workspace_id" >&2
  
  local fetch_url="${USABLE_API_BASE}/workspaces/${workspace_id}/mcp-system-prompt"
  
  local response
  if ! response=$(curl -sS -w "\n%{http_code}" \
    -X GET "$fetch_url" \
    -H "Authorization: Bearer $USABLE_API_TOKEN"); then
    echo "::warning::Failed to fetch optional MCP system prompt, continuing without it" >&2
    return 1
  fi
  
  local http_code
  http_code=$(echo "$response" | tail -n1)
  local body
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" != "200" ]; then
    echo "::warning::Failed to fetch MCP system prompt (HTTP $http_code), continuing without it" >&2
    return 1
  fi
  
  # Current workspace responses use systemPrompt; retain older text formats.
  local content
  if echo "$body" | jq empty >/dev/null 2>&1; then
    if ! content=$(echo "$body" | jq -er '.systemPrompt // .content // .prompt | select(type == "string" and length > 0)' 2>/dev/null); then
      echo "::warning::MCP system prompt response has no nonempty text prompt, continuing without it" >&2
      return 1
    fi
  else
    # Preserve plain-text responses, but do not mistake malformed JSON for a prompt.
    if [[ "$body" =~ ^[[:space:]]*[\{\[] ]] || [ -z "$body" ]; then
      echo "::warning::Invalid MCP system prompt response, continuing without it" >&2
      return 1
    fi
    content="$body"
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
    if mcp_content=$(fetch_mcp_system_prompt "$WORKSPACE_ID"); then
      echo "$mcp_content" > "$MCP_SYSTEM_PROMPT_FILE"
      has_mcp_system=true
      echo "✅ MCP system prompt fetched successfully"
      echo "Size: $(wc -c < "$MCP_SYSTEM_PROMPT_FILE") bytes"
    else
      echo "Continuing with the action system prompt and user prompt"
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
    # Use CUSTOM_PROMPT_FILE (set by action.yml) or fall back to PROMPT_FILE (for local testing)
    CUSTOM_PROMPT_FILE="${CUSTOM_PROMPT_FILE:-${PROMPT_FILE:-}}"
    
    if [ -n "$CUSTOM_PROMPT_FILE" ] && [ -f "$CUSTOM_PROMPT_FILE" ]; then
      echo "Using static prompt file: $CUSTOM_PROMPT_FILE"
      cp "$CUSTOM_PROMPT_FILE" "$USER_PROMPT_FILE"
      has_user_prompt=true
      echo "✅ Static prompt loaded"
      echo "Size: $(wc -c < "$USER_PROMPT_FILE") bytes"
    else
      echo "::error::No user prompt file provided or file not found"
      echo "  CUSTOM_PROMPT_FILE: ${CUSTOM_PROMPT_FILE:-not set}"
      echo "  PROMPT_FILE: ${PROMPT_FILE:-not set}"
      echo "  File exists: $([ -f "${CUSTOM_PROMPT_FILE:-}" ] && echo "yes" || echo "no")"
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
