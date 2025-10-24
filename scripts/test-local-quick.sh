#!/usr/bin/env bash
# Quick local test - minimal setup required
# Usage: ./scripts/test-local-quick.sh [base-branch] [head-branch]

set -euo pipefail

BASE="${1:-main}"
HEAD="${2:-$(git rev-parse --abbrev-ref HEAD)}"

echo "🧪 Quick Validation Test"
echo "Base: $BASE → Head: $HEAD"
echo ""

# Check environment
if [ -z "${GEMINI_SERVICE_ACCOUNT_KEY:-}" ]; then
  echo "❌ Set GEMINI_SERVICE_ACCOUNT_KEY first"
  exit 1
fi

if [ -z "${USABLE_API_TOKEN:-}" ]; then
  echo "❌ Set USABLE_API_TOKEN first"
  exit 1
fi

# Quick config
export BASE_BRANCH="$BASE"
export HEAD_BRANCH="$HEAD"
export WORKSPACE_ID="${WORKSPACE_ID:-60c10ca2-4115-4c1a-b6d7-04ac39fd3938}"
export GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
export PR_NUMBER="999"
export PR_TITLE="Local Test"
export PR_DESCRIPTION="Testing locally"
export PR_URL="https://github.com/test/local"
PR_AUTHOR="$(git config user.name)"
export PR_AUTHOR
export PR_LABELS="test"
export PROMPT_FILE=".github/prompts/pr-validation.md"
ACTION_PATH="$(pwd)"
export ACTION_PATH
export MCP_SECRET_NAME="USABLE_API_TOKEN"
export MCP_SERVER_URL="https://usable.dev/api/mcp"
export ALLOW_WEB_FETCH="false"
export MAX_RETRIES="2"
export USE_DYNAMIC_PROMPTS="false"
export MERGE_CUSTOM_PROMPT="true"

# Setup and run (source to preserve environment variables)
source scripts/setup-gemini.sh && \
source scripts/setup-mcp.sh && \
source scripts/fetch-prompt.sh && \
source scripts/validate.sh

echo ""
echo "✅ Results in /tmp/validation-report.md"

