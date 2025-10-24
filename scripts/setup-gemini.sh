#!/usr/bin/env bash
set -euo pipefail

echo "::group::Setting up Gemini Authentication"

# Get the secret value from the environment using the secret name
# For GitHub Actions, SECRET_NAME is set. For local testing, use default.
SECRET_NAME="${SECRET_NAME:-GEMINI_SERVICE_ACCOUNT_KEY}"
SECRET_VALUE="${!SECRET_NAME:-}"

if [ -z "$SECRET_VALUE" ]; then
  echo "::error::Service account key not found in environment variable: $SECRET_NAME"
  echo "Please ensure the secret is set in your workflow: env.$SECRET_NAME"
  echo "For local testing: export GEMINI_SERVICE_ACCOUNT_KEY='<your-service-account-json>'"
  exit 1
fi

# Handle both base64-encoded (GitHub Actions) and raw JSON (local testing)
# Try to detect if it's already JSON by checking for JSON structure
if [[ "$SECRET_VALUE" =~ ^\{.*\}$ ]] || [[ "$SECRET_VALUE" =~ ^[[:space:]]*\{ ]]; then
  # Looks like JSON, write directly
  echo "$SECRET_VALUE" > /tmp/service-account.json
else
  # Assume base64-encoded, decode it
  if ! echo "$SECRET_VALUE" | base64 -d > /tmp/service-account.json 2>/dev/null; then
    echo "::error::Failed to decode base64 service account key"
    echo "For local testing, use raw JSON: export GEMINI_SERVICE_ACCOUNT_KEY=\$(cat service-account.json)"
    exit 1
  fi
fi

# Verify JSON format
if ! jq empty /tmp/service-account.json 2>/dev/null; then
  echo "::error::Invalid JSON format in service account key"
  rm -f /tmp/service-account.json
  exit 1
fi

# Set restrictive permissions
chmod 600 /tmp/service-account.json

# Extract project ID and set up environment
PROJECT_ID=$(jq -r '.project_id' /tmp/service-account.json)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" == "null" ]; then
  echo "::error::Could not extract project_id from service account key"
  rm -f /tmp/service-account.json
  exit 1
fi

# Set environment variables for Vertex AI
export GOOGLE_APPLICATION_CREDENTIALS="/tmp/service-account.json"
export GOOGLE_GENAI_USE_VERTEXAI="true"
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
export GOOGLE_CLOUD_LOCATION="${GOOGLE_CLOUD_LOCATION:-us-central1}"

# Write to GITHUB_ENV for subsequent steps (if in GitHub Actions)
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "GOOGLE_APPLICATION_CREDENTIALS=/tmp/service-account.json"
    echo "GOOGLE_GENAI_USE_VERTEXAI=true"
    echo "GOOGLE_CLOUD_PROJECT=$PROJECT_ID"
    echo "GOOGLE_CLOUD_LOCATION=${GOOGLE_CLOUD_LOCATION}"
  } >> "$GITHUB_ENV"
fi

echo "✅ Gemini authentication configured"
echo "  Project: $PROJECT_ID"
echo "  Location: ${GOOGLE_CLOUD_LOCATION}"
echo "::endgroup::"
