#!/usr/bin/env bash
set -euo pipefail

# Local testing script for Usable PR Validator
# Run this from the repository root to test validation locally

echo "🧪 Local PR Validator Test"
echo "============================"
echo ""

# Check required environment variables
REQUIRED_VARS=(
  "GEMINI_SERVICE_ACCOUNT_KEY"
  "USABLE_API_TOKEN"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    MISSING_VARS+=("$var")
  fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo "❌ Missing required environment variables:"
  for var in "${MISSING_VARS[@]}"; do
    echo "   - $var"
  done
  echo ""
  echo "Set them with:"
  echo "  export GEMINI_SERVICE_ACCOUNT_KEY='<your-service-account-json>'"
  echo "  export USABLE_API_TOKEN='<your-usable-api-token>'"
  exit 1
fi

# Set defaults for optional vars
export BASE_BRANCH="${BASE_BRANCH:-main}"
export HEAD_BRANCH="${HEAD_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
export WORKSPACE_ID="${WORKSPACE_ID:-60c10ca2-4115-4c1a-b6d7-04ac39fd3938}"
export GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
export MCP_SERVER_URL="${MCP_SERVER_URL:-https://usable.dev/api/mcp}"
export ALLOW_WEB_FETCH="${ALLOW_WEB_FETCH:-false}"
export MAX_RETRIES="${MAX_RETRIES:-2}"

# PR context (for local testing, use dummy values)
export PR_NUMBER="${PR_NUMBER:-0}"
export PR_TITLE="${PR_TITLE:-Local Test Run}"
export PR_DESCRIPTION="${PR_DESCRIPTION:-Testing PR validation locally}"
export PR_URL="${PR_URL:-https://github.com/local/test}"
export PR_AUTHOR="${PR_AUTHOR:-$(git config user.name || echo "unknown")}"
export PR_LABELS="${PR_LABELS:-test}"

# Prompt file
export PROMPT_FILE="${PROMPT_FILE:-.github/prompts/pr-validation.md}"
export USE_DYNAMIC_PROMPTS="${USE_DYNAMIC_PROMPTS:-false}"
export MERGE_CUSTOM_PROMPT="${MERGE_CUSTOM_PROMPT:-true}"

# Secret names (for consistency with action)
export MCP_SECRET_NAME="USABLE_API_TOKEN"

echo "📋 Configuration:"
echo "   Base Branch: $BASE_BRANCH"
echo "   Head Branch: $HEAD_BRANCH"
echo "   Workspace ID: $WORKSPACE_ID"
echo "   Model: $GEMINI_MODEL"
echo "   Prompt File: $PROMPT_FILE"
echo ""

# Check if prompt file exists
if [ "$USE_DYNAMIC_PROMPTS" != "true" ] && [ ! -f "$PROMPT_FILE" ]; then
  echo "❌ Prompt file not found: $PROMPT_FILE"
  echo ""
  echo "Either:"
  echo "  1. Create the prompt file at: $PROMPT_FILE"
  echo "  2. Set PROMPT_FILE to an existing file"
  echo "  3. Use dynamic prompts: export USE_DYNAMIC_PROMPTS=true PROMPT_FRAGMENT_ID=<uuid>"
  exit 1
fi

# Install Gemini CLI if not present
if ! command -v gemini &> /dev/null; then
  echo "📦 Installing Gemini CLI..."
  npm install -g @google/generative-ai-cli
fi

# Check Gemini CLI version
echo "✅ Gemini CLI: $(gemini --version 2>/dev/null || echo 'installed')"
echo ""

# Get action path (current directory)
export ACTION_PATH="$(pwd)"

# Run setup scripts (source them to preserve environment variables)
echo "🔧 Setting up authentication..."
source scripts/setup-gemini.sh

echo ""
echo "🔌 Setting up MCP server..."
source scripts/setup-mcp.sh

echo ""
echo "📝 Fetching prompts..."
source scripts/fetch-prompt.sh

echo ""
echo "🚀 Running validation..."
echo ""
source scripts/validate.sh

echo ""
echo "✅ Validation complete!"
echo ""
echo "📊 Results:"
if [ -f "/tmp/validation-report.md" ]; then
  echo "   Report: /tmp/validation-report.md"
  cat /tmp/validation-report.md
else
  echo "   ⚠️ No report generated"
fi

echo ""
echo "📁 Artifacts:"
echo "   Full Output: /tmp/validation-full-output.md"
echo "   Report: /tmp/validation-report.md"
echo "   Prompt: /tmp/validation-prompt.txt"

