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

# Generate compact diff summary with file paths and line ranges
generate_diff_summary() {
  local base_ref="origin/${BASE_BRANCH}"
  local head_ref="origin/${HEAD_BRANCH}"
  
  # Verify refs exist before generating summary
  if ! git rev-parse "$base_ref" >/dev/null 2>&1; then
    echo "⚠️ **Unable to generate diff summary**: Base ref not found: $base_ref"
    return 1
  fi
  
  if ! git rev-parse "$head_ref" >/dev/null 2>&1; then
    echo "⚠️ **Unable to generate diff summary**: Head ref not found: $head_ref"
    return 1
  fi
  
  local file_count
  file_count=$(git diff --name-only "$base_ref...$head_ref" 2>/dev/null | wc -l | tr -d ' ')
  
  if [ "$file_count" -eq 0 ]; then
    echo "ℹ️ **No files changed** in this PR"
    return 0
  fi
  
  echo "## 📋 Changed Files Summary"
  echo ""
  echo "**Total files changed**: $file_count"
  echo ""
  echo "**Instructions for Validation:**"
  echo "1. Review the list below to understand what changed"
  echo "2. Read specific files using: \`cat path/to/file.ts\`"
  echo "3. Check related files when needed (imports, configs, etc.)"
  echo "4. Focus validation on the modified line ranges shown"
  echo ""
  echo "---"
  echo ""
  
  # Get list of changed files with their change stats
  git diff --numstat "$base_ref...$head_ref" 2>/dev/null | while read -r additions deletions filepath; do
    # Skip if filepath is empty
    [ -z "$filepath" ] && continue
    
    echo "### \`$filepath\`"
    
    # Handle binary files (shown as "-" in numstat)
    if [ "$additions" = "-" ]; then
      echo "- **Type**: Binary file"
    else
      echo "- **Changes**: +${additions} lines, -${deletions} lines"
      
      # Get the line ranges that changed (unified diff format gives us @@ markers)
      # -U0 means no context, just the changed lines
      local line_ranges
      line_ranges=$(git diff -U0 "$base_ref...$head_ref" -- "$filepath" 2>/dev/null | \
        grep "^@@" | \
        sed 's/@@ -[0-9,]* +\([0-9,]*\) @@.*/Line \1/' | \
        head -10 | \
        tr '\n' ', ' | \
        sed 's/, $//')
      
      if [ -n "$line_ranges" ]; then
        echo "- **Modified ranges**: $line_ranges"
      fi
    fi
    echo ""
  done
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
  
  # Generate compact diff summary
  echo "Generating diff summary..." >&2
  DIFF_SUMMARY=$(generate_diff_summary 2>&1)
  local summary_exit_code=$?
  
  if [ $summary_exit_code -ne 0 ]; then
    echo "::warning::Failed to generate diff summary. Gemini will need to discover changes manually." >&2
    DIFF_SUMMARY="⚠️ **Diff summary generation failed**

Please use git commands to discover changes:
\`\`\`bash
git diff --name-only origin/${BASE_BRANCH}...origin/${HEAD_BRANCH}
git diff origin/${BASE_BRANCH}...origin/${HEAD_BRANCH}
\`\`\`"
  else
    echo "✅ Diff summary generated successfully" >&2
    echo "   Files in summary: $(echo "$DIFF_SUMMARY" | grep -c "^###" || echo "0")" >&2
  fi
  
  # Create PR context block
  PR_CONTEXT="**PR #${PR_NUMBER}**: ${PR_TITLE}

**URL**: ${PR_URL}
**Author**: @${PR_AUTHOR}
**Labels**: ${PR_LABELS:-none}

**Description**:
${PR_DESCRIPTION:-No description provided}

---

${DIFF_SUMMARY}"

  # Add override comment if provided
  if [ -n "$OVERRIDE_COMMENT" ]; then
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

  # Read prompt template
  PROMPT_CONTENT=$(cat "$prompt_file")
  
  # Replace placeholders using bash string replacement (NOT sed)
  # This handles special characters safely
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{WEB_FETCH_POLICY\}\}/${web_fetch_policy}}"
  PROMPT_CONTENT="${PROMPT_CONTENT//\{\{PR_CONTEXT\}\}/${PR_CONTEXT}}"
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
    echo "::error::Prompt file is empty after placeholder replacement" >&2
    echo "  Original file size: $(wc -c < "$prompt_file") bytes" >&2
    echo "  This usually means:" >&2
    echo "  1. Prompt template file was empty" >&2
    echo "  2. GitHub environment variables not set" >&2
    echo "  3. Placeholder replacement failed" >&2
    return 1
  fi
  
  echo "$output_file"
}

# Run Gemini validation with retry logic
run_gemini() {
  local prompt_file="$1"
  local retry_count=0
  local max_retries="${MAX_RETRIES:-2}"
  
  while [ $retry_count -le $max_retries ]; do
    echo "Attempt $((retry_count + 1))/$((max_retries + 1)): Running Gemini validation..."
    
    # Debug: Check prompt file
    if [ ! -f "$prompt_file" ]; then
      echo "::error::Prompt file does not exist: $prompt_file"
      return 1
    fi
    
    echo "Prompt file: $prompt_file"
    echo "Prompt file size: $(wc -c < "$prompt_file") bytes"
    echo "Prompt file lines: $(wc -l < "$prompt_file") lines"
    
    # Show detailed execution info
    echo "🤖 Running Gemini CLI"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Model: $GEMINI_MODEL"
    echo "Prompt size: $(wc -c < "$prompt_file") bytes"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Run Gemini CLI and capture output
    set +e  # Temporarily disable exit on error to capture exit code
    
    # Just use tee to show and save output - simple and effective
    gemini -y -m "$GEMINI_MODEL" --prompt "$(cat "$prompt_file")" 2>&1 | tee /tmp/validation-full-output.md
    local exit_code=$?
    
    set -e  # Re-enable exit on error
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ $exit_code -eq 0 ]; then
      echo "✅ Gemini CLI completed successfully (exit code: 0)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      return 0
    else
      echo "❌ Gemini CLI failed (exit code: $exit_code)"
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

# Extract validation report from Gemini output
extract_report() {
  local full_output="$1"
  local report_file="/tmp/validation-report.md"
  
  # Strategy 1: Look for "# PR Validation Report" header
  if grep -q "# PR Validation Report" "$full_output"; then
    echo "Extracting report using Strategy 1: PR Validation Report header"
    sed -n '/# PR Validation Report/,$p' "$full_output" > "$report_file"
    return 0
  fi
  
  # Strategy 2: Look for "## Summary" section
  if grep -q "## Summary" "$full_output"; then
    echo "Extracting report using Strategy 2: Summary section"
    sed -n '/## Summary/,$p' "$full_output" > "$report_file"
    echo "# PR Validation Report" | cat - "$report_file" > /tmp/temp && mv /tmp/temp "$report_file"
    return 0
  fi
  
  # Strategy 3: Look for "## Critical Violations" section
  if grep -q "## Critical Violations" "$full_output"; then
    echo "Extracting report using Strategy 3: Critical Violations section"
    sed -n '/## Critical Violations/,$p' "$full_output" > "$report_file"
    echo "# PR Validation Report" | cat - "$report_file" > /tmp/temp && mv /tmp/temp "$report_file"
    return 0
  fi
  
  # Strategy 4: Use full output with warning
  echo "::warning::Could not find report markers. Using full output."
  echo "::group::Gemini Full Output (first 50 lines)"
  head -50 "$full_output" || echo "Could not read output file"
  echo "::endgroup::"
  
  if [ ! -f "$full_output" ]; then
    echo "::error::Full output file does not exist: $full_output"
    return 1
  fi
  
  cp "$full_output" "$report_file"
  
  if [ ! -f "$report_file" ]; then
    echo "::error::Failed to create report file: $report_file"
    return 1
  fi
  
  echo "✅ Report file created (using full output)"
  return 0
}

# Parse validation results and set GitHub outputs
parse_results() {
  local report_file="$1"
  
  # Check for PASS/FAIL status
  local validation_status
  local validation_passed
  local critical_issues
  
  if grep -q -i "Status.*PASS" "$report_file" || grep -q "✅" "$report_file"; then
    validation_status="passed"
    validation_passed="true"
  else
    validation_status="failed"
    validation_passed="false"
  fi
  
  # Count critical issues (looking for unchecked critical violations)
  # Strip any whitespace/newlines and ensure we get a clean integer
  critical_issues=$(grep -c "^- \[ \] \*\*" "$report_file" 2>/dev/null || echo "0")
  critical_issues=$(echo "$critical_issues" | tr -d '\n\r' | tr -d ' ')
  
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
  
  # Run Gemini validation
  if ! run_gemini "$prompt_with_replacements"; then
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
  
  # Extract report from output
  echo "::group::Extracting validation report"
  echo "Full output file: /tmp/validation-full-output.md"
  if [ -f "/tmp/validation-full-output.md" ]; then
    echo "✅ Full output file exists ($(wc -l < /tmp/validation-full-output.md) lines)"
  else
    echo "::error::Full output file does not exist!"
    exit 1
  fi
  
  if ! extract_report "/tmp/validation-full-output.md"; then
    echo "::error::Failed to extract validation report"
    echo "::endgroup::"
    exit 1
  fi
  echo "::endgroup::"
  
  # Parse results and set outputs
  echo "Parsing validation results..."
  
  # Set GitHub outputs and get results
  if [ -f "/tmp/validation-report.md" ]; then
    # parse_results writes to GITHUB_OUTPUT and returns display values
    results=$(parse_results "/tmp/validation-report.md")
    
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

