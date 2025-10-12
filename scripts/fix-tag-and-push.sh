#!/bin/bash

# Script to fix the 'latest' tag and push changes
# This script:
# 1. Pushes the main branch
# 2. Deletes the local 'latest' tag
# 3. Creates a new 'latest' tag at HEAD
# 4. Force pushes the updated 'latest' tag to remote

set -e  # Exit on error

echo "🔍 Current state:"
echo "  HEAD: $(git rev-parse HEAD)"
echo "  Local 'latest' tag: $(git rev-parse latest 2>/dev/null || echo 'not found')"
echo ""

echo "📤 Step 1: Pushing main branch..."
git push origin main

echo "✅ Main branch pushed successfully!"
echo ""

echo "🏷️  Step 2: Fixing 'latest' tag..."

# Delete local 'latest' tag if it exists
if git rev-parse latest >/dev/null 2>&1; then
    echo "  Deleting local 'latest' tag..."
    git tag -d latest
fi

# Create new 'latest' tag at HEAD
echo "  Creating new 'latest' tag at HEAD..."
git tag latest

# Force push the 'latest' tag to remote
echo "  Force pushing 'latest' tag to remote..."
git push origin latest --force

echo ""
echo "✅ All done! Your changes have been pushed and 'latest' tag is updated."
echo ""
echo "📊 Final state:"
echo "  HEAD: $(git rev-parse HEAD)"
echo "  'latest' tag: $(git rev-parse latest)"

