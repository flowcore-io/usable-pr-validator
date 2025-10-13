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
    echo "Prompt file: $prompt_file"
    echo "Prompt size: $(wc -c < "$prompt_file") bytes"
    echo "Command: gemini -y -m $GEMINI_MODEL --prompt <prompt_content>"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "::group::📋 Prompt Content Preview (first 50 lines)"
    head -50 "$prompt_file"
    echo "::endgroup::"
    echo ""
    echo "📤 Sending request to Gemini..."
    echo ""
    
    # Create temporary files for output capture
    local combined_output="/tmp/gemini-combined-output.log"
    local clean_output="/tmp/gemini-clean-output.log"
    
    # Run Gemini CLI with explicit output streaming
    # Show EVERYTHING - raw, unfiltered output in chronological order
    echo "::group::🤖 Gemini CLI Complete Raw Output (stdout + stderr merged)"
    echo "════════════════════════════════════════"
    echo "COMPLETE RAW OUTPUT FROM GEMINI CLI:"
    echo "This shows ALL output in the order it appears"
    echo "════════════════════════════════════════"
    echo ""
    
    set +e  # Temporarily disable exit on error to capture exit code
    
    # Run gemini and capture EVERYTHING (stdout + stderr merged), display it, and save it
    # Using 2>&1 merges stderr into stdout so we see everything in chronological order
    gemini -y -m "$GEMINI_MODEL" --prompt "$(cat "$prompt_file")" 2>&1 | tee "$combined_output"
    local exit_code=$?
    
    echo ""
    echo "════════════════════════════════════════"
    if [ -f "$combined_output" ]; then
      echo "Combined output: $(wc -l < "$combined_output") lines, $(wc -c < "$combined_output") bytes"
    fi
    echo "════════════════════════════════════════"
    
    set -e  # Re-enable exit on error
    echo "::endgroup::"
    
    # Extract just the AI response (clean output) from the combined output
    # The AI response typically starts after all the status messages
    # We need to skip lines like "Loaded cached credentials", "MCP ERROR", etc.
    if [ -f "$combined_output" ]; then
      # Strategy: Look for the start of markdown content (lines starting with # or ##)
      # Skip all the CLI status messages at the beginning
      echo ""
      echo "::group::📄 Extracted AI Response (clean)"
      
      # Try to find where the actual AI response starts
      # Look for common patterns like "# " at start of line
      if grep -q "^# " "$combined_output"; then
        # Extract from first markdown header onwards
        sed -n '/^# /,$p' "$combined_output" > "$clean_output"
        echo "✅ Extracted AI response starting from markdown header"
      else
        # Fallback: just copy everything (in case format is different)
        cp "$combined_output" "$clean_output"
        echo "⚠️ No markdown header found, using full output"
      fi
      
      if [ -f "$clean_output" ] && [ -s "$clean_output" ]; then
        echo "════════════════════════════════════════"
        cat "$clean_output"
        echo ""
        echo "════════════════════════════════════════"
        echo "Clean output: $(wc -l < "$clean_output") lines, $(wc -c < "$clean_output") bytes"
        echo "════════════════════════════════════════"
        
        # Copy clean output to expected location
        cp "$clean_output" /tmp/validation-full-output.md
      else
        echo "⚠️ No clean output extracted, using combined output"
        cp "$combined_output" /tmp/validation-full-output.md
      fi
      
      echo "::endgroup::"
    fi
    
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
      
      # Error details are already shown above in the raw output sections
      echo "⚠️ Check the raw output sections above for error details"
      
      # Check if it's a retryable error
      local is_retryable=false
      if [ -f "$combined_output" ] && grep -q -E "(429|503|timeout|rate limit)" "$combined_output"; then
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

