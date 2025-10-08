#!/usr/bin/env bash
set -euo pipefail

echo "::group::Setting up Gemini Authentication"

# Get the secret value from the environment using the secret name
SECRET_VALUE="${!SECRET_NAME:-}"

if [ -z "$SECRET_VALUE" ]; then
  echo "::error::Service account key not found in environment variable: $SECRET_NAME"
  echo "Please ensure the secret is set in your workflow: env.$SECRET_NAME"
  exit 1
fi

# Decode base64-encoded service account key
echo "$SECRET_VALUE" | base64 -d > /tmp/service-account.json

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

# Write to GITHUB_ENV for subsequent steps
echo "GOOGLE_APPLICATION_CREDENTIALS=/tmp/service-account.json" >> $GITHUB_ENV
echo "GOOGLE_GENAI_USE_VERTEXAI=true" >> $GITHUB_ENV
echo "GOOGLE_CLOUD_PROJECT=$PROJECT_ID" >> $GITHUB_ENV
echo "GOOGLE_CLOUD_LOCATION=${GOOGLE_CLOUD_LOCATION}" >> $GITHUB_ENV

echo "✅ Gemini authentication configured"
echo "  Project: $PROJECT_ID"
echo "  Location: ${GOOGLE_CLOUD_LOCATION}"
echo "::endgroup::"
