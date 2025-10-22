#!/usr/bin/env bash
set -euo pipefail

echo "::group::Running PR Validation"

# Function to verify git refs are available and test diff
verify_git_refs() {
  local base="${BASE_BRANCH}"
  local head="${HEAD_BRANCH}"
  local has_error=false
  
  echo "::group::🔍 Verifying Git Diff Setup"
  echo "Base branch: $base"
  echo "Head branch: $head"
  echo ""
  
  # Try to resolve base ref
  echo "Checking base ref..."
  local base_resolved=false
  for ref_format in "origin/$base" "$base" "refs/heads/$base" "refs/remotes/origin/$base"; do
    if git rev-parse "$ref_format" >/dev/null 2>&1; then
      echo "✅ Base ref available: $ref_format"
      local base_commit
      base_commit=$(git rev-parse "$ref_format")
      echo "   Commit: $base_commit"
      base_resolved=true
      break
    fi
  done
  
  if [ "$base_resolved" = false ]; then
    echo "::error::❌ Base ref not found: $base"
    echo "Available remote branches:"
    git branch -r | head -10
    has_error=true
  fi
  
  # Try to resolve head ref
  echo ""
  echo "Checking head ref..."
  local head_resolved=false
  for ref_format in "origin/$head" "$head" "HEAD" "refs/heads/$head" "refs/remotes/origin/$head"; do
    if git rev-parse "$ref_format" >/dev/null 2>&1; then
      echo "✅ Head ref available: $ref_format"
      local head_commit
      head_commit=$(git rev-parse "$ref_format")
      echo "   Commit: $head_commit"
      head_resolved=true
      break
    fi
  done
  
  if [ "$head_resolved" = false ]; then
    echo "::error::❌ Head ref not found: $head"
    echo "Current HEAD:"
    git rev-parse HEAD || echo "HEAD not available"
    has_error=true
  fi
  
  # Test git diff commands
  echo ""
  echo "Testing git diff commands..."
  
  # Test three-dot diff (what AI will use)
  if git diff --name-only "origin/$base...origin/$head" >/dev/null 2>&1; then
    echo "✅ Three-dot diff works: origin/$base...origin/$head"
    local file_count
    file_count=$(git diff --name-only "origin/$base...origin/$head" | wc -l)
    echo "   Files changed: $file_count"
  elif git diff --name-only "origin/$base..$head" >/dev/null 2>&1; then
    echo "⚠️  Three-dot diff failed, but two-dot diff works"
    local file_count
    file_count=$(git diff --name-only "origin/$base..$head" | wc -l)
    echo "   Files changed: $file_count"
  elif git diff --name-only "$base...$head" >/dev/null 2>&1; then
    echo "⚠️  Standard diff works without origin/ prefix"
    local file_count
    file_count=$(git diff --name-only "$base...$head" | wc -l)
    echo "   Files changed: $file_count"
  else
    echo "::error::❌ Git diff command failed!"
    echo "Attempted formats:"
    echo "  - origin/$base...origin/$head"
    echo "  - origin/$base..$head"
    echo "  - $base...$head"
    has_error=true
  fi
  
  if [ "$has_error" = true ]; then
    echo ""
    echo "::error::❌ Git diff setup has errors. Validation may fail."
    echo "The AI will attempt to use fallback methods, but results may be incomplete."
    echo "::endgroup::"
    return 1
  else
    echo ""
    echo "✅ Git diff setup verified successfully"
    echo "::endgroup::"
    return 0
  fi
}

# Get file stats for the PR
get_file_stats() {
  local base="${BASE_BRANCH}"
  local head="${HEAD_BRANCH}"

  echo "Getting file statistics for PR..."

  # Try to get the diff stat
  local file_stats=""
  if git diff --stat "origin/$base...origin/$head" 2>/dev/null; then
    file_stats=$(git diff --stat "origin/$base...origin/$head" 2>/dev/null || echo "Unable to retrieve file statistics")
  elif git diff --stat "$base...$head" 2>/dev/null; then
    file_stats=$(git diff --stat "$base...$head" 2>/dev/null || echo "Unable to retrieve file statistics")
  else
    file_stats="Unable to retrieve file statistics. Use git commands to explore changes."
  fi

  # Also get list of changed files
  local changed_files=""
  if git diff --name-only "origin/$base...origin/$head" 2>/dev/null; then
    changed_files=$(git diff --name-only "origin/$base...origin/$head" 2>/dev/null | head -100)
  elif git diff --name-only "$base...$head" 2>/dev/null; then
    changed_files=$(git diff --name-only "$base...$head" 2>/dev/null | head -100)
  fi

  # Format the output
  local output="## Files Changed

\`\`\`
$file_stats
\`\`\`

## Changed Files List
\`\`\`
$changed_files
\`\`\`

**Note**: Use \`git --no-pager diff origin/$base...origin/$head -- <file_path>\` to examine specific files."

  echo "$output"
}

# Prepare prompt with placeholder replacement
#
# Uses bash native string replacement for simplicity and safety.
# For current scope (8 placeholders), this is efficient and readable.
#
# Alternative approaches considered:
# - envsubst: Would require careful escaping of $ symbols in prompts
# - sed: More complex escaping, harder to maintain
# - External templating tool: Adds dependency, overkill for current needs
#
# Current approach handles:
# - Multi-line content safely
# - Special characters without escaping issues
# - Fast execution (no external process spawning per placeholder)
prepare_prompt() {
  local prompt_file="$1"
  local output_file="/tmp/validation-prompt.txt"

  # Create PR context block
  PR_CONTEXT="**PR #${PR_NUMBER}**: ${PR_TITLE}

**URL**: ${PR_URL}
**Author**: @${PR_AUTHOR}
**Labels**: ${PR_LABELS:-none}

**Description**:
${PR_DESCRIPTION:-No description provided}"

  # Add override comment if provided
  if [ -n "${OVERRIDE_COMMENT:-}" ]; then
    PR_CONTEXT="${PR_CONTEXT}

**🔄 Override/Clarification Comment** (from @${COMMENT_AUTHOR:-unknown}):
\`\`\`
${OVERRIDE_COMMENT}
\`\`\`
"
  fi

  # Prepare web fetch policy based on flag
  local web_fetch_policy
  if [ "${ALLOW_WEB_FETCH:-false}" = "true" ]; then
    web_fetch_policy="**Web fetch is ENABLED** for this validation. You may use the \`web_fetch\` tool to retrieve external resources if needed for validation (e.g., checking external documentation, standards, or references). Use this capability responsibly and only when necessary."
  else
    web_fetch_policy="**Web fetch is DISABLED** for this validation. DO NOT use the \`web_fetch\` tool or attempt to download content from URLs. All validation must be performed using only the git repository contents, PR context, and Usable MCP knowledge base."
  fi

  # Get file statistics
  local file_stats
  file_stats=$(get_file_stats)

  # Read prompt template
  PROMPT_CONTENT=$(cat "$prompt_file")

  # Replace placeholders using bash string replacement (NOT sed)
  # This handles special characters safely
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{WEB_FETCH_POLICY\}\}/${web_fetch_policy}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{PR_CONTEXT\}\}/${PR_CONTEXT}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{FILE_STATS\}\}/${file_stats}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{BASE_BRANCH\}\}/${BASE_BRANCH}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{HEAD_BRANCH\}\}/${HEAD_BRANCH}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{PR_TITLE\}\}/${PR_TITLE}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{PR_DESCRIPTION\}\}/${PR_DESCRIPTION:-No description provided}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{PR_NUMBER\}\}/${PR_NUMBER}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{PR_URL\}\}/${PR_URL}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{PR_AUTHOR\}\}/${PR_AUTHOR}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{PR_LABELS\}\}/${PR_LABELS:-none}}"

  # Write to temp file
  echo "$PROMPT_CONTENT" > "$output_file"

  # Verify prompt is not empty
  if [ ! -s "$output_file" ]; then
    echo "::error::Prompt file is empty after placeholder replacement"
    echo "  Original file size: $(wc -c < "$prompt_file") bytes"
    echo "  This usually means:"
    echo "  1. Prompt template file was empty"
    echo "  2. GitHub environment variables not set"
    echo "  3. Placeholder replacement failed"
    return 1
  fi

  echo "$output_file"
}

# Run ForgeCode validation with retry logic
run_forgecode() {
  local prompt_file="$1"
  local retry_count=0
  local max_retries="${MAX_RETRIES:-2}"

  while [ $retry_count -le $max_retries ]; do
    echo "Attempt $((retry_count + 1))/$((max_retries + 1)): Running ForgeCode validation..."

    # Debug: Check prompt file
    if [ ! -f "$prompt_file" ]; then
      echo "::error::Prompt file does not exist: $prompt_file"
      return 1
    fi

    echo "Prompt file: $prompt_file"
    echo "Prompt file size: $(wc -c < "$prompt_file") bytes"
    echo "Prompt file lines: $(wc -l < "$prompt_file") lines"

    # Show detailed execution info
    echo "🤖 Running ForgeCode CLI"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Provider: ${PROVIDER:-auto}"
    echo "Model: ${MODEL}"
    echo "Prompt size: $(wc -c < "$prompt_file") bytes"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Configure ForgeCode with the specified model
    if [ -n "${MODEL:-}" ]; then
      echo "Configuring ForgeCode model: ${MODEL}"
      forge config set --model "${MODEL}" 2>&1 || echo "Warning: Could not set model config"
    fi

    # Run ForgeCode CLI and capture output
    set +e  # Temporarily disable exit on error to capture exit code

    # Use -p flag for non-interactive mode with prompt from file
    # Note: Removed --verbose to get clean output without debugging info
    forge -p "$(cat "$prompt_file")" 2>&1 | tee /tmp/validation-full-output.md
    local exit_code=$?

    set -e  # Re-enable exit on error

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ $exit_code -eq 0 ]; then
      echo "✅ ForgeCode CLI completed successfully (exit code: 0)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      return 0
    else
      echo "❌ ForgeCode CLI failed (exit code: $exit_code)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""

      # Error details are shown above in the output
      echo "⚠️ Check the output above for error details"

      # Check if it's a retryable error
      local is_retryable=false
      if [ -f /tmp/validation-full-output.md ] && grep -q -E "(429|503|timeout|rate limit)" /tmp/validation-full-output.md; then
        is_retryable=true
      fi

      if [ "$is_retryable" = true ]; then
        retry_count=$((retry_count + 1))

        if [ $retry_count -le $max_retries ]; then
          wait_time=$((2 ** retry_count))
          echo "⏳ Rate limit or timeout detected. Retrying after ${wait_time} seconds..."
          sleep $wait_time
        else
          echo "::error::Maximum retries reached. Validation failed."
          return 1
        fi
      else
        # Non-retryable error
        echo "::error::Non-retryable error occurred. See error details above."
        return 1
      fi
    fi
  done

  return 1
}

# Extract validation report from ForgeCode output
extract_report() {
  local full_output="$1"
  local report_file="/tmp/validation-report.md"
  local clean_output="/tmp/validation-clean-output.md"
  
  # First, strip ANSI escape codes from the output
  # This handles color codes and formatting that might interfere with pattern matching
  if command -v sed &> /dev/null; then
    sed 's/\x1b\[[0-9;]*m//g' "$full_output" > "$clean_output"
  else
    cp "$full_output" "$clean_output"
  fi
  
  # Strategy 1: Look for "# PR Validation Report" header
  if grep -q "# PR Validation Report" "$clean_output"; then
    echo "Extracting report using Strategy 1: PR Validation Report header"
    sed -n '/# PR Validation Report/,$p' "$clean_output" > "$report_file"
    return 0
  fi
  
  # Strategy 2: Look for "## Summary" section
  if grep -q "## Summary" "$clean_output"; then
    echo "Extracting report using Strategy 2: Summary section"
    sed -n '/## Summary/,$p' "$clean_output" > "$report_file"
    echo "# PR Validation Report" | cat - "$report_file" > /tmp/temp && mv /tmp/temp "$report_file"
    return 0
  fi
  
  # Strategy 3: Look for "## Critical Violations" section
  if grep -q "## Critical Violations" "$clean_output"; then
    echo "Extracting report using Strategy 3: Critical Violations section"
    sed -n '/## Critical Violations/,$p' "$clean_output" > "$report_file"
    echo "# PR Validation Report" | cat - "$report_file" > /tmp/temp && mv /tmp/temp "$report_file"
    return 0
  fi
  
  # Strategy 4: Use full output with warning
  echo "::warning::Could not find report markers. Using full output."
  echo "::group::ForgeCode Full Output (first 50 lines)"
  head -50 "$clean_output" || echo "Could not read output file"
  echo "::endgroup::"
  
  if [ ! -f "$clean_output" ]; then
    echo "::error::Clean output file does not exist: $clean_output"
    return 1
  fi
  
  cp "$clean_output" "$report_file"
  
  if [ ! -f "$report_file" ]; then
    echo "::error::Failed to create report file: $report_file"
    return 1
  fi
  
  echo "✅ Report file created (using full output)"
  return 0
}

# Parse validation results from JSON and set GitHub outputs
parse_results() {
  local json_file="/tmp/validation-report.json"
  
  # Extract values from JSON
  local validation_status
  local validation_passed
  local critical_issues
  
  # Get status from JSON
  local status=$(jq -r '.validationOutcome.status' "$json_file")
  
  if [ "$status" = "PASS" ]; then
    validation_status="passed"
    validation_passed="true"
  else
    validation_status="failed"
    validation_passed="false"
  fi
  
  # Get critical issues count from JSON
  critical_issues=$(jq -r '.validationOutcome.criticalIssuesCount' "$json_file")
  
  # Ensure we have a valid integer (default to 0 if empty or invalid)
  if ! [[ "$critical_issues" =~ ^[0-9]+$ ]]; then
    critical_issues=0
  fi
  
  # If status is fail but no critical issues found, set to 1
  if [ "$validation_status" = "failed" ] && [ "$critical_issues" -eq 0 ]; then
    critical_issues=1
  fi
  
  # Write outputs using heredoc delimiter (multiline-safe, prevents injection)
  {
    echo "validation_status<<EOF"
    echo "$validation_status"
    echo "EOF"
    echo "validation_passed<<EOF"
    echo "$validation_passed"
    echo "EOF"
    echo "critical_issues<<EOF"
    echo "$critical_issues"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
  
  echo "✅ Outputs written successfully"
  
  # Export for display
  echo "$validation_status|$validation_passed|$critical_issues"
}

# Main execution
main() {
  # Verify git refs before starting validation
  if ! verify_git_refs; then
    echo "::warning::Git diff verification failed. Continuing anyway, but validation may fail."
  fi
  
  # Determine which prompt file to use
  local actual_prompt_file=""
  
  # Check if fetch-prompt.sh created a merged/final prompt (takes precedence)
  if [ -f "/tmp/dynamic-prompt.md" ]; then
    echo "Using prompt prepared by fetch-prompt.sh (includes system prompt if configured)"
    actual_prompt_file="/tmp/dynamic-prompt.md"
  elif [ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ]; then
    echo "Using static prompt file: $PROMPT_FILE"
    actual_prompt_file="$PROMPT_FILE"
  else
    echo "::error::No valid prompt file found"
    echo "  - Merged prompt exists: $([ -f "/tmp/dynamic-prompt.md" ] && echo "yes" || echo "no")"
    echo "  - PROMPT_FILE: ${PROMPT_FILE:-not set}"
    echo "  - Custom prompt exists: $([ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ] && echo "yes" || echo "no")"
    exit 1
  fi
  
  # Prepare prompt with placeholder replacement
  echo "Preparing validation prompt..."
  prompt_with_replacements=$(prepare_prompt "$actual_prompt_file")
  
  echo "Prompt prepared: $prompt_with_replacements"

  # Run ForgeCode validation
  if ! run_forgecode "$prompt_with_replacements"; then
    echo "::error::Validation execution failed"
    
    # Set failed outputs using heredoc delimiter
    {
      echo "validation_status<<EOF"
      echo "error"
      echo "EOF"
      echo "validation_passed<<EOF"
      echo "false"
      echo "EOF"
      echo "critical_issues<<EOF"
      echo "0"
      echo "EOF"
    } >> "$GITHUB_OUTPUT"
    
    echo "❌ Outputs set to error state"
    exit 1
  fi
  
  # Check if JSON report was created
  echo "::group::Processing validation report"
  
  if [ ! -f "/tmp/validation-report.json" ]; then
    echo "::error::JSON report file not created by ForgeCode"
    echo "Expected file: /tmp/validation-report.json"
    echo ""
    echo "::group::ForgeCode output (for debugging)"
    if [ -f "/tmp/validation-full-output.md" ]; then
      head -100 "/tmp/validation-full-output.md" || echo "Could not read output file"
    fi
    echo "::endgroup::"
    echo "::endgroup::"
    exit 1
  fi
  
  echo "✅ JSON report found"
  
  # Validate JSON
  if ! jq empty "/tmp/validation-report.json" 2>/dev/null; then
    echo "::error::Invalid JSON in report file"
    echo "::group::JSON content"
    cat "/tmp/validation-report.json" || echo "Could not read JSON file"
    echo "::endgroup::"
    echo "::endgroup::"
    exit 1
  fi
  
  echo "✅ JSON is valid"
  
  # Construct markdown report from JSON
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if ! "$SCRIPT_DIR/construct-markdown.sh" "/tmp/validation-report.json" "/tmp/validation-report.md"; then
    echo "::error::Failed to construct markdown from JSON"
    echo "::endgroup::"
    exit 1
  fi
  
  echo "✅ Markdown report constructed"
  echo "::endgroup::"
  
  # Parse results and set outputs
  echo "Parsing validation results..."
  
  # Set GitHub outputs and get results
  if [ -f "/tmp/validation-report.json" ]; then
    # parse_results writes to GITHUB_OUTPUT and returns display values
    results=$(parse_results)
    
    # Extract values for display (pipe-separated format)
    IFS='|' read -r validation_status validation_passed critical_issues <<< "$results"
    
    # Display summary
    echo ""
    echo "================================"
    echo "📊 Validation Results"
    echo "================================"
    cat "/tmp/validation-report.md" | head -50
    echo ""
    echo "================================"
    echo "Status: $validation_status"
    echo "Critical Issues: $critical_issues"
    echo "================================"
  else
    echo "::error::Report file not generated"
    
    # Set error outputs using heredoc delimiter
    {
      echo "validation_status<<EOF"
      echo "error"
      echo "EOF"
      echo "validation_passed<<EOF"
      echo "false"
      echo "EOF"
      echo "critical_issues<<EOF"
      echo "0"
      echo "EOF"
    } >> "$GITHUB_OUTPUT"
    
    echo "❌ Outputs set to error state (no report)"
    exit 1
  fi
  
  echo "::endgroup::"
}

# Run main function
main

