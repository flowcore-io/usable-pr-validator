#!/usr/bin/env bash
set -euo pipefail

echo "::group::Setting up LLM Provider Authentication"

# Determine which provider to use
PROVIDER="${PROVIDER:-auto}"

echo "Provider mode: $PROVIDER"

# Function to check if an API key is available
check_api_key() {
  local key_name="$1"
  local key_value="${!key_name:-}"

  if [ -n "$key_value" ]; then
    echo "✅ $key_name is available"
    return 0
  else
    echo "❌ $key_name is not set"
    return 1
  fi
}

# Auto-detect provider if set to auto
if [ "$PROVIDER" = "auto" ]; then
  echo "Auto-detecting provider from environment variables..."

  if check_api_key "OPENROUTER_API_KEY"; then
    PROVIDER="openrouter"
    echo "🎯 Auto-detected provider: OpenRouter"
  elif check_api_key "ANTHROPIC_API_KEY"; then
    PROVIDER="anthropic"
    echo "🎯 Auto-detected provider: Anthropic"
  elif check_api_key "OPENAI_API_KEY"; then
    PROVIDER="openai"
    echo "🎯 Auto-detected provider: OpenAI"
  else
    echo "::error::No API key found in environment"
    echo "Please set one of: OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY"
    exit 1
  fi
fi

# Validate that the required API key is present
case "$PROVIDER" in
  openrouter)
    if ! check_api_key "OPENROUTER_API_KEY"; then
      echo "::error::OPENROUTER_API_KEY is required for OpenRouter provider"
      exit 1
    fi
    ;;
  anthropic)
    if ! check_api_key "ANTHROPIC_API_KEY"; then
      echo "::error::ANTHROPIC_API_KEY is required for Anthropic provider"
      exit 1
    fi
    ;;
  openai)
    if ! check_api_key "OPENAI_API_KEY"; then
      echo "::error::OPENAI_API_KEY is required for OpenAI provider"
      exit 1
    fi
    ;;
  *)
    echo "::error::Unknown provider: $PROVIDER"
    echo "Supported providers: openrouter, anthropic, openai, auto"
    exit 1
    ;;
esac

# Export provider for downstream scripts
echo "PROVIDER=$PROVIDER" >> "$GITHUB_ENV" 2>/dev/null || export PROVIDER="$PROVIDER"

echo "✅ Provider authentication configured: $PROVIDER"
echo "::endgroup::"
