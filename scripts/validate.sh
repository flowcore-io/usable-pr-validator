#!/bin/bash
set -euo pipefail

echo "::group::Running PR Validation"

# Prepare prompt with placeholder replacement
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

  # Read prompt template
  PROMPT_CONTENT=$(cat "$prompt_file")
  
  # Replace placeholders using bash string replacement (NOT sed)
  # This handles special characters safely
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
    
    # Run Gemini CLI using --prompt flag instead of stdin
    if gemini -y -m "$GEMINI_MODEL" --prompt "$(cat "$prompt_file")" > /tmp/validation-full-output.md 2>&1; then
      echo "✅ Validation completed successfully"
      return 0
    else
      exit_code=$?
      echo "⚠️ Gemini CLI exited with code: $exit_code"
      
      # Check if it's a retryable error
      if grep -q -E "(429|503|timeout|rate limit)" /tmp/validation-full-output.md; then
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -le $max_retries ]; then
          wait_time=$((2 ** retry_count))
          echo "Retrying after ${wait_time} seconds..."
          sleep $wait_time
        else
          echo "::error::Maximum retries reached. Validation failed."
          return 1
        fi
      else
        # Non-retryable error
        echo "::error::Non-retryable error occurred"
        cat /tmp/validation-full-output.md
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

# Parse validation results
parse_results() {
  local report_file="$1"
  
  # Check for PASS/FAIL status
  if grep -q -i "Status.*PASS" "$report_file" || grep -q "✅" "$report_file"; then
    validation_status="passed"
    validation_passed="true"
  else
    validation_status="failed"
    validation_passed="false"
  fi
  
  # Count critical issues (looking for unchecked critical violations)
  critical_issues=$(grep -c "^- \[ \] \*\*" "$report_file" || echo "0")
  
  # If status is fail but no critical issues found, set to 1
  if [ "$validation_status" == "failed" ] && [ "$critical_issues" -eq 0 ]; then
    critical_issues=1
  fi
  
  echo "validation_status=$validation_status"
  echo "validation_passed=$validation_passed"
  echo "critical_issues=$critical_issues"
}

# Main execution
main() {
  # Prepare prompt with placeholder replacement
  echo "Preparing validation prompt..."
  prompt_with_replacements=$(prepare_prompt "$PROMPT_FILE")
  
  echo "Prompt prepared: $prompt_with_replacements"
  
  # Run Gemini validation
  if ! run_gemini "$prompt_with_replacements"; then
    echo "::error::Validation execution failed"
    
    # Set failed outputs
    echo "validation_status=failed" >> "$GITHUB_OUTPUT"
    echo "validation_passed=false" >> "$GITHUB_OUTPUT"
    echo "critical_issues=1" >> "$GITHUB_OUTPUT"
    
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
  
  # Set GitHub outputs
  if [ -f "/tmp/validation-report.md" ]; then
    results=$(parse_results "/tmp/validation-report.md")
    
    # Write outputs to GITHUB_OUTPUT file
    echo "$results" >> "$GITHUB_OUTPUT"
    
    # Extract values for display
    validation_status=$(echo "$results" | grep "^validation_status=" | cut -d= -f2)
    validation_passed=$(echo "$results" | grep "^validation_passed=" | cut -d= -f2)
    critical_issues=$(echo "$results" | grep "^critical_issues=" | cut -d= -f2)
    
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
    exit 1
  fi
  
  echo "::endgroup::"
}

# Run main function
main
