#!/usr/bin/env bash
set -euo pipefail

echo "::group::Running PR Validation"

SCRIPT_DIR="${ACTION_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GROUNDING_LEDGER="${USABLE_GROUNDING_LEDGER:-/tmp/usable-grounding-ledger.jsonl}"
REQUIRED_FRAGMENTS_FILE="${USABLE_REQUIRED_FRAGMENTS_FILE:-/tmp/usable-required-fragments.txt}"
REQUIRED_GROUNDING_FILE="${USABLE_REQUIRED_GROUNDING_FILE:-/tmp/usable-required-grounding.md}"

publish_safe_error_report() {
  local summary="${1:-Validation failed before a publishable report was available.}"
  local safe_file
  safe_file=$(mktemp /tmp/validation-report.safe.XXXXXX)
  chmod 600 "$safe_file"
  cat > "$safe_file" <<EOF
# PR Validation Report

## Summary
$summary

## Critical Violations ❌
- [ ] **Validation infrastructure failure**: No validated assistant report is available for publication.

## Validation Outcome
- **Status**: FAIL ❌
- **Critical Issues**: 1
- **Important Issues**: 0
- **Suggestions**: 0
EOF
  mv -f "$safe_file" /tmp/validation-report.md
}

write_outputs() {
  local validation_status="$1"
  local validation_passed="$2"
  local critical_issues="$3"
  local grounding_status="$4"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "validation_status=$validation_status"
      echo "validation_passed=$validation_passed"
      echo "critical_issues=$critical_issues"
      echo "grounding_status=$grounding_status"
    } >> "$GITHUB_OUTPUT"
  fi
}

grounding_result() {
  "$SCRIPT_DIR/scripts/check-grounding-ledger.py" \
    --required "$REQUIRED_FRAGMENTS_FILE" \
    --ledger "$GROUNDING_LEDGER"
}

json_field() {
  python3 -c 'import json,sys; value=json.loads(sys.argv[1]);
for key in sys.argv[2].split("."):
    value=value[key]
print(len(value) if isinstance(value, list) else value)' "$1" "$2"
}

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

# Generate compact diff summary with file paths, change status, and line ranges.
#
# Each file is annotated with its change status (ADDED / MODIFIED / DELETED / RENAMED)
# so the validating LLM knows NOT to try reading deleted files. Previous versions
# emitted a flat file list which caused the LLM to repeatedly fail tool calls on
# deleted files and occasionally trip the doom-loop detector.
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

  # Build a temp file mapping `filepath<TAB>STATUS` so the numstat loop below
  # can annotate each entry. We use a temp file instead of a bash associative
  # array for portability (bash 3 on macOS, the while-read subshell, etc).
  local status_file
  status_file=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$status_file'" RETURN

  git diff --name-status "$base_ref...$head_ref" 2>/dev/null | \
    while IFS=$'\t' read -r status_code path_a path_b; do
      local status_label=""
      local display_path="$path_a"
      case "$status_code" in
        A)   status_label="ADDED" ;;
        M)   status_label="MODIFIED" ;;
        D)   status_label="DELETED" ;;
        T)   status_label="TYPE-CHANGED" ;;
        R*)  status_label="RENAMED from $path_a"; display_path="$path_b" ;;
        C*)  status_label="COPIED from $path_a"; display_path="$path_b" ;;
        *)   status_label="CHANGED" ;;
      esac
      printf '%s\t%s\n' "$display_path" "$status_label" >> "$status_file"
    done

  # Helper to look up a file's status; defaults to "CHANGED" if not found.
  lookup_status() {
    local needle="$1"
    local line
    line=$(grep -F -m 1 $'\t' <(awk -F'\t' -v p="$needle" '$1==p {print}' "$status_file"))
    if [ -n "$line" ]; then
      echo "$line" | cut -f2-
    else
      echo "CHANGED"
    fi
  }

  echo "## 📋 Changed Files Summary"
  echo ""
  echo "**Total files changed**: $file_count"
  echo ""
  echo "**Instructions for Validation:**"
  echo "1. Review the list below to understand what changed"
  echo "2. Each file is annotated with its **Status** (ADDED / MODIFIED / DELETED / RENAMED)"
  echo "3. **Read** files with Status ADDED, MODIFIED, RENAMED, or TYPE-CHANGED using: \`cat path/to/file.ts\`"
  echo "4. **DO NOT** try to read files with Status DELETED — they no longer exist in the working tree. If your read fails with 'File not found', stop retrying and trust the status annotation."
  echo "5. Check related files when needed (imports, configs, etc.)"
  echo "6. Focus validation on the modified line ranges shown"
  echo ""
  echo "---"
  echo ""

  # Get list of changed files with their change stats
  git diff --numstat "$base_ref...$head_ref" 2>/dev/null | while read -r additions deletions filepath; do
    # Skip if filepath is empty
    [ -z "$filepath" ] && continue

    # numstat uses "old => new" notation for renames; peel off the new path
    # so the status lookup matches what name-status emitted.
    case "$filepath" in
      *" => "*)
        filepath=$(printf '%s' "$filepath" | sed -E 's/.*=> *//' | tr -d '{}')
        ;;
    esac

    local file_status
    file_status=$(lookup_status "$filepath")

    echo "### \`$filepath\`"
    echo "- **Status**: $file_status"

    # Handle binary files (shown as "-" in numstat)
    if [ "$additions" = "-" ]; then
      echo "- **Type**: Binary file"
    else
      echo "- **Changes**: +${additions} lines, -${deletions} lines"

      if [ "$file_status" = "DELETED" ]; then
        echo "- **Note**: File was deleted — do NOT attempt to read it. Inspect the diff below (or \`git show HEAD^:$filepath\`) if you need to see its former contents."
      else
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
    echo "::warning::Failed to generate diff summary. AI will need to discover changes manually." >&2
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
  OVERRIDE_COMMENT="${OVERRIDE_COMMENT:-}"
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

  if [ -f "$REQUIRED_GROUNDING_FILE" ]; then
    PROMPT_CONTENT="${PROMPT_CONTENT}

---

## Action-Owned Usable Grounding

The original MCP \`get-memory-fragment-content\` tool is disabled because affected model clients can generate invalid overloaded payloads. Keep using MCP search for discovery. Read any additionally discovered fragment only with:

\`python3 ${SCRIPT_DIR}/scripts/read-usable-fragment.py FRAGMENT_UUID\`

Do not retry a failed deterministic read with alternate or placeholder arguments. Any helper failure makes grounding incomplete and the action will fail outside the model. The following required sources were prefetched and verified before model execution:

$(cat "$REQUIRED_GROUNDING_FILE")"
  fi
  
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
  
  while [ $retry_count -le "$max_retries" ]; do
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

    # Feed the prompt via stdin, NOT as an argv argument. A large PR diff makes
    # the prompt exceed the kernel's per-argument cap (MAX_ARG_STRLEN, 128KB on
    # Linux) → "Argument list too long" (exit 126). gemini reads piped stdin as
    # the prompt when stdin is not a TTY (cli/src/gemini.tsx). `--prompt` is also
    # deprecated upstream. Keep the provider transcript private: fragment bodies
    # and other grounding content must not be copied into the public job log.
    : > /tmp/validation-full-output.md
    : > /tmp/validation-provider-stderr.log
    chmod 600 /tmp/validation-full-output.md /tmp/validation-provider-stderr.log
    gemini -y -m "$GEMINI_MODEL" --output-format json < "$prompt_file" > /tmp/validation-full-output.md 2> /tmp/validation-provider-stderr.log
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
      
      echo "⚠️ Provider transcript retained privately for structured report extraction"
      
      # Check if it's a retryable error. Includes transient upstream provider
      # failures (OpenRouter 504/530, generic "Provider returned error",
      # connection resets) in addition to the classic rate-limit signals, so
      # flaky LLM backends don't burn the whole validation run.
      local is_retryable=false
      if grep -q -i -E "(429|503|504|530|timeout|rate[- ]?limit|provider returned error|unmapped|ECONNRESET|EAI_AGAIN|socket hang up|deadline exceeded)" \
         /tmp/validation-full-output.md /tmp/validation-provider-stderr.log 2>/dev/null; then
        is_retryable=true
      fi
      
      if [ "$is_retryable" = true ]; then
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -le "$max_retries" ]; then
          wait_time=$((2 ** retry_count))
          echo "⏳ Rate limit or timeout detected. Retrying after ${wait_time} seconds..."
          sleep $wait_time
        else
          echo "::error::Maximum retries reached. Validation failed."
          return 1
        fi
      else
        # Non-retryable error
        echo "::error::Non-retryable provider error occurred."
        return 1
      fi
    fi
  done
  
  return 1
}

# Run OpenCode validation with retry logic.
# Args: $1 prompt file, $2 opencode-provider (optional, defaults to OPENCODE_PROVIDER),
#       $3 model id (optional, defaults to OPENCODE_MODEL).
# Returns: 0 success | 1 non-retryable failure | 2 retryable failure with retries exhausted (caller may fallback).
run_opencode() {
  local prompt_file="$1"
  local opencode_provider="${2:-${OPENCODE_PROVIDER:-openrouter}}"
  local model="${3:-${OPENCODE_MODEL:-moonshotai/kimi-k2.5}}"
  local retry_count=0
  local max_retries="${MAX_RETRIES:-2}"
  local full_model="${opencode_provider}/${model}"

  while [ $retry_count -le "$max_retries" ]; do
    echo "Attempt $((retry_count + 1))/$((max_retries + 1)): Running OpenCode validation (${full_model})..."

    # Debug: Check prompt file
    if [ ! -f "$prompt_file" ]; then
      echo "::error::Prompt file does not exist: $prompt_file"
      return 1
    fi

    echo "Prompt file: $prompt_file"
    echo "Prompt file size: $(wc -c < "$prompt_file") bytes"
    echo "Prompt file lines: $(wc -l < "$prompt_file") lines"

    # Show detailed execution info
    echo "🤖 Running OpenCode CLI"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Model: $full_model"
    echo "Prompt size: $(wc -c < "$prompt_file") bytes"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Run OpenCode CLI and capture output
    set +e  # Temporarily disable exit on error to capture exit code

    # Feed the prompt via stdin, NOT as an argv argument. A large PR diff makes
    # the prompt exceed the kernel's per-argument cap (MAX_ARG_STRLEN, 128KB on
    # Linux) → "Argument list too long" (exit 126). opencode reads piped stdin as
    # the message when stdin is not a TTY (cli/cmd/run.ts). `set -o pipefail`
    # Keep the provider transcript private rather than teeing fragment bodies or
    # other model context into the public job log.
    : > /tmp/validation-full-output.md
    : > /tmp/validation-provider-stderr.log
    chmod 600 /tmp/validation-full-output.md /tmp/validation-provider-stderr.log
    opencode run --format json -m "$full_model" < "$prompt_file" > /tmp/validation-full-output.md 2> /tmp/validation-provider-stderr.log
    local exit_code=$?

    set -e  # Re-enable exit on error

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ $exit_code -eq 0 ]; then
      echo "✅ OpenCode CLI completed successfully (exit code: 0)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      return 0
    else
      echo "❌ OpenCode CLI failed (exit code: $exit_code)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""

      echo "⚠️ Provider transcript retained privately for structured report extraction"

      # Check if it's a retryable error. Includes transient upstream provider
      # failures (OpenRouter 504/530, generic "Provider returned error",
      # connection resets) in addition to the classic rate-limit signals, so
      # flaky LLM backends don't burn the whole validation run.
      local is_retryable=false
      if grep -q -i -E "(429|503|504|530|timeout|rate[- ]?limit|provider returned error|unmapped|ECONNRESET|EAI_AGAIN|socket hang up|deadline exceeded)" \
         /tmp/validation-full-output.md /tmp/validation-provider-stderr.log 2>/dev/null; then
        is_retryable=true
      fi

      if [ "$is_retryable" = true ]; then
        retry_count=$((retry_count + 1))

        if [ $retry_count -le "$max_retries" ]; then
          wait_time=$((2 ** retry_count))
          echo "⏳ Rate limit or timeout detected. Retrying after ${wait_time} seconds..."
          sleep $wait_time
        else
          echo "::error::Maximum retries reached. Validation failed (retryable)."
          return 2
        fi
      else
        # Non-retryable error — caller should NOT fall back to a different provider.
        echo "::error::Non-retryable provider error occurred."
        return 1
      fi
    fi
  done

  return 2
}

# Extract validation report from AI output
extract_report() {
  local full_output="$1"
  local provider="$2"
  local candidate_file="$3"
  
  if [ ! -f "$full_output" ]; then
    echo "::error::Full output file does not exist: $full_output"
    return 1
  fi

  if ! "$SCRIPT_DIR/scripts/extract-provider-report.py" \
      --provider "$provider" "$full_output" > "$candidate_file"; then
    echo "::error::Could not isolate the final assistant response from provider output"
    return 1
  fi

  if ! "$SCRIPT_DIR/scripts/parse-validation-report.py" "$candidate_file" >/dev/null; then
    echo "::error::AI output did not contain a valid structured final verdict"
    return 1
  fi

  echo "✅ Structured report extracted"
  return 0
}

# Parse validation results and set GitHub outputs
parse_results() {
  local report_file="$1"
  local parsed validation_status validation_passed critical_issues
  parsed=$("$SCRIPT_DIR/scripts/parse-validation-report.py" "$report_file") || return 1
  validation_status=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["status"])' "$parsed")
  validation_passed=$(python3 -c 'import json,sys; print(str(json.loads(sys.argv[1])["passed"]).lower())' "$parsed")
  critical_issues=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["critical_issues"])' "$parsed")
  echo "$validation_status|$validation_passed|$critical_issues"
}

# Main execution
main() {
  local grounding_json grounding_rc=0 grounding_status
  rm -f /tmp/validation-report.md /tmp/validation-report.candidate.* /tmp/validation-report.safe.*
  grounding_json=$(grounding_result) || grounding_rc=$?
  if [ "$grounding_rc" -eq 2 ]; then
    echo "::error::Grounding ledger is malformed"
    write_outputs "error" "false" "0" "incomplete"
    exit 1
  fi
  grounding_status=$(json_field "$grounding_json" status)
  if [ "${GROUNDING_PREFETCH_FAILED:-false}" = "true" ] || [ "$grounding_status" = "incomplete" ]; then
    cat > /tmp/validation-report.md <<EOF
# PR Validation Report

## Summary
Validation did not run because deterministic Usable grounding was incomplete.

## Critical Violations ❌
- [ ] **Validation infrastructure failure**: One or more declared required fragments could not be retrieved and verified.

## Validation Outcome
- **Status**: FAIL ❌
- **Critical Issues**: 1
- **Important Issues**: 0
- **Suggestions**: 0
EOF
    "$SCRIPT_DIR/scripts/enforce-grounding-report.py" /tmp/validation-report.md \
      --status incomplete \
      --required-count "$(json_field "$grounding_json" required_count)" \
      --missing-count "$(json_field "$grounding_json" missing_required)" \
      --failed-count "$(json_field "$grounding_json" failed_attempts)"
    write_outputs "error" "false" "1" "incomplete"
    echo "::error::Validation execution stopped because required grounding is incomplete"
    exit 1
  fi

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
  
  # Run validation with the configured provider.
  # Use `|| rc=$?` (not `set +e`) because run_opencode/run_gemini toggle errexit
  # internally to capture the CLI's exit code, which clobbers any outer set +e.
  local provider="${PROVIDER:-opencode}"
  local rc=0
  if [ "$provider" = "opencode" ]; then
    run_opencode "$prompt_with_replacements" "${OPENCODE_PROVIDER:-}" "${OPENCODE_MODEL:-}" || rc=$?

    # Fallback: only when primary exhausted retries on retryable errors (rc=2)
    # AND a fallback opencode-provider is configured. Non-retryable failures (rc=1)
    # bypass fallback because switching providers won't fix a malformed prompt/auth.
    if [ "$rc" -eq 2 ] && [ -n "${FALLBACK_OPENCODE_PROVIDER:-}" ] && [ -n "${FALLBACK_OPENCODE_MODEL:-}" ]; then
      echo "::warning::Primary opencode/${OPENCODE_PROVIDER:-}/${OPENCODE_MODEL:-} exhausted retries on retryable errors. Falling back to ${FALLBACK_OPENCODE_PROVIDER}/${FALLBACK_OPENCODE_MODEL}."
      rc=0
      run_opencode "$prompt_with_replacements" "${FALLBACK_OPENCODE_PROVIDER}" "${FALLBACK_OPENCODE_MODEL}" || rc=$?
    fi
  else
    run_gemini "$prompt_with_replacements" || rc=$?
  fi

  if [ "$rc" -ne 0 ]; then
    echo "::error::Validation execution failed"

    publish_safe_error_report "Validation execution failed before a valid final assistant report was available."
    write_outputs "error" "false" "0" "$grounding_status"
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
    publish_safe_error_report "The provider did not produce structured output for validation."
    exit 1
  fi

  local candidate_file
  candidate_file=$(mktemp /tmp/validation-report.candidate.XXXXXX)
  chmod 600 "$candidate_file"
  if ! extract_report "/tmp/validation-full-output.md" "$provider" "$candidate_file"; then
    rm -f "$candidate_file"
    publish_safe_error_report "The provider completed, but its final assistant response was not a valid validation report."
    echo "::error::Failed to extract validation report"
    write_outputs "error" "false" "0" "$grounding_status"
    echo "::endgroup::"
    exit 1
  fi
  echo "::endgroup::"

  grounding_rc=0
  grounding_json=$(grounding_result) || grounding_rc=$?
  if [ "$grounding_rc" -eq 2 ]; then
    echo "::error::Grounding ledger is malformed after validation"
    rm -f "$candidate_file"
    publish_safe_error_report "The grounding ledger became invalid after provider execution."
    write_outputs "error" "false" "0" "incomplete"
    exit 1
  fi
  grounding_status=$(json_field "$grounding_json" status)
  if ! "$SCRIPT_DIR/scripts/enforce-grounding-report.py" "$candidate_file" \
    --status "$grounding_status" \
    --required-count "$(json_field "$grounding_json" required_count)" \
    --missing-count "$(json_field "$grounding_json" missing_required)" \
    --failed-count "$(json_field "$grounding_json" failed_attempts)"; then
    rm -f "$candidate_file"
    publish_safe_error_report "The assistant report could not be safely combined with the action-owned grounding result."
    write_outputs "error" "false" "0" "$grounding_status"
    exit 1
  fi
  if ! "$SCRIPT_DIR/scripts/parse-validation-report.py" "$candidate_file" >/dev/null; then
    rm -f "$candidate_file"
    publish_safe_error_report "The grounded assistant report failed final validation and was not published."
    write_outputs "error" "false" "0" "$grounding_status"
    exit 1
  fi
  mv -f "$candidate_file" /tmp/validation-report.md
  
  # Parse results and set outputs
  echo "Parsing validation results..."
  
  # Set GitHub outputs and get results
  if [ -f "/tmp/validation-report.md" ]; then
    # parse_results writes to GITHUB_OUTPUT and returns display values
    results=$(parse_results "/tmp/validation-report.md")
    
    # Extract values for display (pipe-separated format)
    IFS='|' read -r validation_status validation_passed critical_issues <<< "$results"
    if [ "$grounding_status" = "incomplete" ]; then
      write_outputs "error" "false" "$critical_issues" "$grounding_status"
    else
      write_outputs "$validation_status" "$validation_passed" "$critical_issues" "$grounding_status"
    fi
    
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
    echo "Grounding Status: $grounding_status"
    echo "================================"
    if [ "$grounding_status" = "incomplete" ]; then
      echo "::error::Validation execution failed because a grounding read was unresolved"
      exit 1
    fi
  else
    echo "::error::Report file not generated"
    
    write_outputs "error" "false" "0" "$grounding_status"
    echo "❌ Outputs set to error state (no report)"
    exit 1
  fi
  
  echo "::endgroup::"
}

# Run main function unless sourced by the contract tests.
if [ "${VALIDATE_SH_LIBRARY_ONLY:-false}" != "true" ]; then
  main
fi

