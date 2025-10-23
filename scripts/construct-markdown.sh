#!/usr/bin/env bash
set -euo pipefail

# Construct markdown comment from JSON validation report
# Usage: construct-markdown.sh <json-file> <output-md-file>

JSON_FILE="${1:-/tmp/validation-report.json}"
OUTPUT_FILE="${2:-/tmp/validation-report.md}"

if [ ! -f "$JSON_FILE" ]; then
  echo "::error::JSON report file not found: $JSON_FILE"
  exit 1
fi

# Verify JSON is valid
if ! jq empty "$JSON_FILE" 2>/dev/null; then
  echo "::error::Invalid JSON in report file"
  exit 1
fi

# Start constructing the markdown report
{
  echo "# PR Validation Report"
  echo ""
  
  # Summary
  echo "## Summary"
  jq -r '.summary' "$JSON_FILE"
  echo ""
  
  # Override information (if present)
  if jq -e '.overrideApplied' "$JSON_FILE" > /dev/null 2>&1; then
    echo "## Override Applied 🔄"
    echo ""
    echo "A deviation from standards has been approved and documented:"
    echo ""
    echo "- **Deviation**: $(jq -r '.overrideApplied.deviation // "N/A"' "$JSON_FILE")"
    echo "- **Justification**: $(jq -r '.overrideApplied.justification // "N/A"' "$JSON_FILE")"
    
    if jq -e '.overrideApplied.fragmentId' "$JSON_FILE" > /dev/null 2>&1; then
      fragment_id=$(jq -r '.overrideApplied.fragmentId' "$JSON_FILE")
      fragment_title=$(jq -r '.overrideApplied.fragmentTitle // "Deviation"' "$JSON_FILE")
      echo "- **Documentation**: Fragment created - ${fragment_title} (ID: ${fragment_id})"
    fi
    
    if jq -e '.overrideApplied.approvedBy' "$JSON_FILE" > /dev/null 2>&1; then
      approved_by=$(jq -r '.overrideApplied.approvedBy' "$JSON_FILE")
      echo "- **Approved by**: @${approved_by}"
    fi
    
    echo ""
    echo "This deviation has been recorded in the knowledge base for future reference."
    echo ""
  fi
  
  # Critical Violations
  echo "## Critical Violations ❌"
  echo ""
  
  critical_count=$(jq '.criticalViolations | length' "$JSON_FILE")
  
  if [ "$critical_count" -eq 0 ]; then
    echo "None found."
  else
    # Iterate through critical violations
    jq -c '.criticalViolations[]' "$JSON_FILE" | while read -r violation; do
      file=$(echo "$violation" | jq -r '.file')
      issue=$(echo "$violation" | jq -r '.issue')
      why=$(echo "$violation" | jq -r '.why')
      fix=$(echo "$violation" | jq -r '.fix')
      code=$(echo "$violation" | jq -r '.code // empty')
      
      echo "- **File**: \`$file\`"
      echo "  - **Issue**: $issue"
      echo "  - **Why**: $why"
      echo "  - **Fix**: $fix"
      
      if [ -n "$code" ]; then
        echo "  - **Code**:"
        echo '  ```'
        echo "$code" | sed 's/^/  /'
        echo '  ```'
      fi
      echo ""
    done
  fi
  
  echo ""
  
  # Important Issues
  echo "## Important Issues ⚠️"
  echo ""
  
  important_count=$(jq '.importantIssues | length' "$JSON_FILE")
  
  if [ "$important_count" -eq 0 ]; then
    echo "None found."
  else
    jq -c '.importantIssues[]' "$JSON_FILE" | while read -r issue; do
      file=$(echo "$issue" | jq -r '.file')
      issue_text=$(echo "$issue" | jq -r '.issue')
      why=$(echo "$issue" | jq -r '.why')
      fix=$(echo "$issue" | jq -r '.fix')
      code=$(echo "$issue" | jq -r '.code // empty')
      
      echo "- **File**: \`$file\`"
      echo "  - **Issue**: $issue_text"
      echo "  - **Why**: $why"
      echo "  - **Fix**: $fix"
      
      if [ -n "$code" ]; then
        echo "  - **Code**:"
        echo '  ```'
        echo "$code" | sed 's/^/  /'
        echo '  ```'
      fi
      echo ""
    done
  fi
  
  echo ""
  
  # Suggestions
  echo "## Suggestions ℹ️"
  echo ""
  
  suggestions_count=$(jq '.suggestions | length' "$JSON_FILE")
  
  if [ "$suggestions_count" -eq 0 ]; then
    echo "None found."
  else
    jq -c '.suggestions[]' "$JSON_FILE" | while read -r suggestion; do
      title=$(echo "$suggestion" | jq -r '.title')
      description=$(echo "$suggestion" | jq -r '.description')
      file=$(echo "$suggestion" | jq -r '.file // empty')
      
      echo "- **$title**: $description"
      
      if [ -n "$file" ]; then
        echo "  - File: \`$file\`"
      fi
      echo ""
    done
  fi
  
  echo ""
  
  # Validation Outcome
  echo "## Validation Outcome"
  echo ""
  
  status=$(jq -r '.validationOutcome.status' "$JSON_FILE")
  critical=$(jq -r '.validationOutcome.criticalIssuesCount' "$JSON_FILE")
  important=$(jq -r '.validationOutcome.importantIssuesCount' "$JSON_FILE")
  suggestions=$(jq -r '.validationOutcome.suggestionsCount' "$JSON_FILE")
  
  if [ "$status" = "PASS" ]; then
    echo "- **Status**: PASS ✅"
  else
    echo "- **Status**: FAIL ❌"
  fi
  
  echo "- **Critical Issues**: $critical"
  echo "- **Important Issues**: $important"
  echo "- **Suggestions**: $suggestions"
  
  # Add rationale if present
  if jq -e '.validationOutcome.rationale' "$JSON_FILE" > /dev/null 2>&1; then
    rationale=$(jq -r '.validationOutcome.rationale' "$JSON_FILE")
    echo ""
    echo "**Rationale**: $rationale"
  fi
  
  # Add metadata if present
  if jq -e '.metadata.triggeredBy' "$JSON_FILE" > /dev/null 2>&1; then
    triggered_by=$(jq -r '.metadata.triggeredBy' "$JSON_FILE")
    echo ""
    echo "- **Triggered by**: $triggered_by"
  fi
  
  if jq -e '.metadata.standardsChecked' "$JSON_FILE" > /dev/null 2>&1; then
    echo ""
    echo "### Standards Checked"
    echo ""
    jq -r '.metadata.standardsChecked[]' "$JSON_FILE" | while read -r standard; do
      echo "- $standard"
    done
  fi
  
} > "$OUTPUT_FILE"

echo "✅ Markdown report constructed: $OUTPUT_FILE"
echo "   Lines: $(wc -l < "$OUTPUT_FILE")"

