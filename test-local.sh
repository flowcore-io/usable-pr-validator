#!/usr/bin/env bash
set -euo pipefail

# Local testing script for PR validation
# This allows you to test the validator locally before pushing to GitHub

echo "🧪 Usable PR Validator - Local Test"
echo "===================================="
echo ""

# Check required environment variables
MISSING_VARS=()

if [ -z "${OPENROUTER_API_KEY:-}${ANTHROPIC_API_KEY:-}${OPENAI_API_KEY:-}" ]; then
  MISSING_VARS+=("At least one of: OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY")
fi

if [ -z "${USABLE_API_TOKEN:-}" ]; then
  MISSING_VARS+=("USABLE_API_TOKEN")
fi

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo "❌ Missing required environment variables:"
  for var in "${MISSING_VARS[@]}"; do
    echo "   - $var"
  done
  echo ""
  echo "Please set these in your environment or .env file"
  echo ""
  echo "Example:"
  echo "  export OPENROUTER_API_KEY='your-key-here'"
  echo "  export USABLE_API_TOKEN='your-token-here'"
  exit 1
fi

# Set default values for local testing
export PROVIDER="${PROVIDER:-auto}"
export MODEL="${MODEL:-anthropic/claude-haiku-4.5}"
export WORKSPACE_ID="${WORKSPACE_ID:-60c10ca2-4115-4c1a-b6d7-04ac39fd3938}"  # Flowcore workspace
export MCP_SERVER_URL="${MCP_SERVER_URL:-https://usable.dev/api/mcp}"

# Git configuration (you can override these)
export BASE_BRANCH="${BASE_BRANCH:-main}"
export HEAD_BRANCH="${HEAD_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"

# PR metadata (simulated for local testing)
export PR_NUMBER="${PR_NUMBER:-0}"
export PR_TITLE="${PR_TITLE:-Local Test: $(git log -1 --pretty=%s)}"
export PR_DESCRIPTION="${PR_DESCRIPTION:-Testing PR validation locally}"
export PR_URL="${PR_URL:-https://github.com/local/test}"
export PR_AUTHOR="${PR_AUTHOR:-$(git config user.name)}"
export PR_LABELS="${PR_LABELS:-test,local}"

# Other settings
export USE_DYNAMIC_PROMPTS="${USE_DYNAMIC_PROMPTS:-false}"
export PROMPT_FILE="${PROMPT_FILE:-./system-prompt.md}"
export MAX_RETRIES="${MAX_RETRIES:-2}"
export ALLOW_WEB_FETCH="${ALLOW_WEB_FETCH:-false}"
# Don't export these if they're empty - ForgeCode treats empty strings as file paths
if [ -n "${OVERRIDE_COMMENT:-}" ]; then
  export OVERRIDE_COMMENT
fi
if [ -n "${COMMENT_AUTHOR:-}" ]; then
  export COMMENT_AUTHOR
fi

# GitHub Actions environment variables (simulated)
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-/tmp/github-output.txt}"
export GITHUB_ENV="${GITHUB_ENV:-/tmp/github-env.txt}"
touch "$GITHUB_OUTPUT" "$GITHUB_ENV"

echo "📋 Test Configuration"
echo "===================="
echo "Provider: $PROVIDER"
echo "Model: $MODEL"
echo "Base Branch: $BASE_BRANCH"
echo "Head Branch: $HEAD_BRANCH"
echo "Workspace: $WORKSPACE_ID"
echo ""

# Check if ForgeCode is installed
if ! command -v forge &> /dev/null; then
  echo "⚠️  ForgeCode CLI not found. Installing..."
  npm install -g forgecode@latest
  echo "✅ ForgeCode installed"
  echo ""
fi

# Verify git refs are available
echo "🔍 Verifying Git Setup"
echo "====================="
if ! git rev-parse "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  echo "⚠️  Base branch origin/$BASE_BRANCH not found. Fetching..."
  git fetch origin "$BASE_BRANCH"
fi

if ! git rev-parse "$HEAD_BRANCH" >/dev/null 2>&1; then
  echo "❌ Head branch $HEAD_BRANCH not found"
  echo "Current branch: $(git rev-parse --abbrev-ref HEAD)"
  exit 1
fi

echo "✅ Git refs verified"
echo ""

# Run provider setup
echo "🔐 Setting up Provider"
echo "====================="
./scripts/setup-provider.sh
echo ""

# Run MCP setup
echo "🔗 Setting up MCP"
echo "================"
# For local testing, MCP_URL is already set and USABLE_API_TOKEN is in the environment
MCP_URL="${MCP_SERVER_URL}" ./scripts/setup-mcp.sh
echo ""

# Check if we should fetch dynamic prompts
if [ "$USE_DYNAMIC_PROMPTS" = "true" ]; then
  echo "📥 Fetching Dynamic Prompts"
  echo "=========================="
  ./scripts/fetch-prompt.sh
  echo ""
fi

# Run validation
echo "🚀 Running Validation"
echo "===================="
echo ""
./scripts/validate.sh

# Show results
echo ""
echo "📊 Validation Results"
echo "===================="
if [ -f "$GITHUB_OUTPUT" ]; then
  echo "GitHub Outputs:"
  cat "$GITHUB_OUTPUT"
  echo ""
fi

if [ -f /tmp/validation-report.md ]; then
  echo "Validation Report:"
  echo "=================="
  cat /tmp/validation-report.md
  echo ""
fi

echo "✅ Local test completed"
echo ""
echo "Artifacts:"
echo "  - Full output: /tmp/validation-full-output.md"
echo "  - Report: /tmp/validation-report.md"
echo "  - GitHub outputs: $GITHUB_OUTPUT"
