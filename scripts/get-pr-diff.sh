#!/usr/bin/env bash
set -euo pipefail

# Helper script to safely get PR diffs with comprehensive error handling
# This script is designed to be called by the AI or validation process

# Inputs (from environment)
BASE_REF="${BASE_BRANCH:-origin/main}"
HEAD_REF="${HEAD_BRANCH:-HEAD}"
DIFF_TYPE="${1:-files}"  # files, full, stats

echo "::group::Getting PR Diff"
echo "Base: $BASE_REF"
echo "Head: $HEAD_REF"
echo "Diff type: $DIFF_TYPE"

# Function to normalize ref names
normalize_ref() {
  local ref="$1"
  
  # Try different ref formats in order of preference
  local ref_candidates=(
    "$ref"
    "origin/$ref"
    "refs/heads/$ref"
    "refs/remotes/origin/$ref"
    "refs/tags/$ref"
  )
  
  for candidate in "${ref_candidates[@]}"; do
    if git rev-parse "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  
  # If nothing works, return original and let git fail with a proper error
  echo "$ref"
  return 1
}

# Function to safely get diff
safe_diff() {
  local base="$1"
  local head="$2"
  local diff_type="$3"
  
  # Normalize refs
  echo "Normalizing refs..."
  local normalized_base
  local normalized_head
  
  if ! normalized_base=$(normalize_ref "$base"); then
    echo "::error::Base ref not found: $base"
    echo "Available branches:"
    git branch -r | head -20
    return 1
  fi
  
  if ! normalized_head=$(normalize_ref "$head"); then
    echo "::error::Head ref not found: $head"
    echo "Available branches:"
    git branch -r | head -20
    return 1
  fi
  
  echo "Normalized base: $normalized_base"
  echo "Normalized head: $normalized_head"
  
  # Verify both refs exist
  if ! git rev-parse "$normalized_base" >/dev/null 2>&1; then
    echo "::error::Cannot resolve base ref: $normalized_base"
    return 1
  fi
  
  if ! git rev-parse "$normalized_head" >/dev/null 2>&1; then
    echo "::error::Cannot resolve head ref: $normalized_head"
    return 1
  fi
  
  # Get the diff
  case "$diff_type" in
    files)
      echo "Getting changed files..."
      if ! git diff --name-only "$normalized_base...$normalized_head" 2>/dev/null; then
        # Fallback to two-dot diff if three-dot fails
        echo "::warning::Three-dot diff failed, using two-dot diff"
        git diff --name-only "$normalized_base..$normalized_head"
      fi
      ;;
    stats)
      echo "Getting diff statistics..."
      if ! git diff --stat "$normalized_base...$normalized_head" 2>/dev/null; then
        echo "::warning::Three-dot diff failed, using two-dot diff"
        git diff --stat "$normalized_base..$normalized_head"
      fi
      ;;
    full)
      echo "Getting full diff..."
      if ! git diff "$normalized_base...$normalized_head" 2>/dev/null; then
        echo "::warning::Three-dot diff failed, using two-dot diff"
        git diff "$normalized_base..$normalized_head"
      fi
      ;;
    *)
      echo "::error::Invalid diff type: $diff_type (must be: files, stats, or full)"
      return 1
      ;;
  esac
}

# Main execution
if safe_diff "$BASE_REF" "$HEAD_REF" "$DIFF_TYPE"; then
  echo "✅ Diff retrieved successfully"
  echo "::endgroup::"
  exit 0
else
  echo "::error::Failed to get diff"
  echo "::endgroup::"
  exit 1
fi

