#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/validator-mcp-config.XXXXXX")
cleanup() {
  rm -rf "$FIXTURE"
  rm -f /tmp/opencode.json /tmp/gemini-settings.json
}
trap cleanup EXIT

run_setup() {
  local provider="$1"
  (
    cd "$FIXTURE"
    USABLE_API_TOKEN="test-token-not-secret" \
      MCP_SECRET_NAME="USABLE_API_TOKEN" \
      MCP_SERVER_URL="https://usable.dev/api/mcp" \
      WORKSPACE_ID="f3c9feef-b8e6-4a23-bda0-0d90cd5162d1" \
      PROVIDER="$provider" \
      OPENCODE_PROVIDER="openrouter" \
      OPENCODE_MODEL="test/model" \
      "$ROOT/scripts/setup-mcp.sh" >/dev/null
  )
}

run_setup opencode
python3 -c 'import json; d=json.load(open("/tmp/opencode.json")); assert d["mcp"]["usable"]["enabled"] is True; assert d["tools"]["usable_get-memory-fragment-content"] is False'

run_setup gemini
python3 -c 'import json; d=json.load(open("/tmp/gemini-settings.json")); s=d["mcpServers"]["usable"]; assert "agentic-search-fragments" not in s.get("excludeTools", []); assert s["excludeTools"] == ["get-memory-fragment-content"]; assert s["headers"]["x-workspace-id"] == "f3c9feef-b8e6-4a23-bda0-0d90cd5162d1"'

echo "MCP fragment-content tool is disabled for OpenCode and Gemini while search remains available."
