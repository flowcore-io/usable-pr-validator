#!/usr/bin/env bash
# Test script for debugging git diff issues
# Usage: ./scripts/test-git-diff.sh [base-branch] [head-branch]

set -euo pipefail

BASE="${1:-main}"
HEAD="${2:-HEAD}"

echo "🔍 Git Diff Diagnostic Tool"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Base: $BASE"
echo "Head: $HEAD"
echo ""

# 1. Check if refs exist
echo "1️⃣  Checking if refs exist..."
echo ""

echo "Base ref formats:"
for ref in "$BASE" "origin/$BASE" "refs/heads/$BASE" "refs/remotes/origin/$BASE" "refs/tags/$BASE"; do
  if git rev-parse "$ref" >/dev/null 2>&1; then
    echo "  ✅ $ref → $(git rev-parse --short "$ref")"
  else
    echo "  ❌ $ref (not found)"
  fi
done

echo ""
echo "Head ref formats:"
for ref in "$HEAD" "origin/$HEAD" "refs/heads/$HEAD" "refs/remotes/origin/$HEAD" "refs/tags/$HEAD"; do
  if git rev-parse "$ref" >/dev/null 2>&1; then
    echo "  ✅ $ref → $(git rev-parse --short "$ref")"
  else
    echo "  ❌ $ref (not found)"
  fi
done

echo ""
echo "2️⃣  Testing git diff commands..."
echo ""

# Test three-dot diff
echo "Three-dot diff (origin/$BASE...origin/$HEAD):"
if git diff --name-only "origin/$BASE...origin/$HEAD" 2>&1; then
  echo "  ✅ Success"
  COUNT=$(git diff --name-only "origin/$BASE...origin/$HEAD" | wc -l)
  echo "  📊 $COUNT files changed"
else
  echo "  ❌ Failed"
fi

echo ""

# Test two-dot diff
echo "Two-dot diff (origin/$BASE..origin/$HEAD):"
if git diff --name-only "origin/$BASE..origin/$HEAD" 2>&1; then
  echo "  ✅ Success"
  COUNT=$(git diff --name-only "origin/$BASE..origin/$HEAD" | wc -l)
  echo "  📊 $COUNT files changed"
else
  echo "  ❌ Failed"
fi

echo ""

# Test without origin prefix
echo "Diff without origin prefix ($BASE...$HEAD):"
if git diff --name-only "$BASE...$HEAD" 2>&1; then
  echo "  ✅ Success"
  COUNT=$(git diff --name-only "$BASE...$HEAD" | wc -l)
  echo "  📊 $COUNT files changed"
else
  echo "  ❌ Failed"
fi

echo ""
echo "3️⃣  Showing changed files (if any)..."
echo ""

if git diff --name-only "origin/$BASE...origin/$HEAD" 2>/dev/null | head -20; then
  echo ""
  echo "✅ Git diff is working correctly"
elif git diff --name-only "$BASE...$HEAD" 2>/dev/null | head -20; then
  echo ""
  echo "✅ Git diff works (without origin/ prefix)"
else
  echo "❌ Git diff is not working"
  echo ""
  echo "Debugging info:"
  echo "Available remote refs:"
  git ls-remote --heads origin | head -10
  echo ""
  echo "Local branches:"
  git branch -a | head -20
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Diagnostic complete"

