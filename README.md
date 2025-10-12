# 🤖 Usable PR Validator

> Validate Pull Requests against your Usable knowledge base standards using Google Gemini AI

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Usable%20PR%20Validator-blue?logo=github)](https://github.com/marketplace/actions/usable-pr-validator)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Powered by Usable](https://img.shields.io/badge/Powered%20by-Usable-6366f1)](https://usable.dev)

## ✨ Features

- 🧠 **AI-Powered Validation**: Uses Google Gemini to understand context and architectural patterns
- 📚 **Usable Integration**: Validate PRs against your team's knowledge base stored in Usable
- 🔌 **MCP Protocol**: Connects directly to Usable's MCP server for real-time standards
- 🎯 **System Prompts**: Organization-wide validation standards fetched from Usable and auto-merged
- 🚀 **Dynamic Prompts**: Fetch latest validation prompts from Usable API (no static files needed!)
- 💬 **Comment-Triggered Revalidation**: Mention `@usable` in PR comments to trigger revalidation with context
- 📝 **Automatic Deviation Documentation**: AI creates knowledge base fragments when deviations are approved
- ⚙️ **Highly Configurable**: Customizable prompts, severity levels, and validation rules
- 🔄 **Reliable**: Automatic retry logic with exponential backoff for API failures
- 💬 **Smart PR Comments**: Updates existing comments to avoid spam
- 📊 **Detailed Reports**: Structured validation reports as artifacts and PR comments
- 🔒 **Secure**: Proper secret handling with automatic cleanup

## 🚀 Quick Start (5 Minutes)

### Prerequisites

1. A Google Cloud project with Vertex AI API enabled
2. A service account key with Vertex AI permissions
3. A Usable account with API token ([get one at usable.dev](https://usable.dev))
4. GitHub repository with pull requests

### Step 1: Create Validation Prompt

Create `.github/prompts/pr-validation.md` in your repository:

```markdown
# PR Validation Instructions

## CRITICAL OUTPUT INSTRUCTION
**START YOUR OUTPUT DIRECTLY WITH:** `# PR Validation Report`

## PR Context
{{PR_CONTEXT}}

## Your Task
Analyze the changes and validate against standards.

### Get PR Changes
```bash
git diff origin/{{BASE_BRANCH}}...{{HEAD_BRANCH}}
```

[See templates/ directory for complete examples]

### Step 2: Add GitHub Secrets

Go to your repository Settings → Secrets → Actions and add:

- `GEMINI_SERVICE_ACCOUNT_KEY`: Base64-encoded service account JSON key

  ```bash
  cat service-account.json | base64
  ```

- `USABLE_API_TOKEN`: Your Usable API token (get from [usable.dev](https://usable.dev) → Settings → API Tokens)

### Step 3: Create Workflow

Create `.github/workflows/pr-validation.yml`:

```yaml
name: PR Validation

on:
  pull_request:
    branches: [main, develop]

permissions:
  contents: read
  pull-requests: write

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: flowcore/usable-pr-validator@latest
        with:
          prompt-file: '.github/prompts/pr-validation.md'
          workspace-id: 'your-workspace-uuid'
        env:
          GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
          USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
```

That's it! Your PRs will now be validated automatically. 🎉

## 📖 Configuration

### Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `prompt-file` | Path to validation prompt markdown file (optional if `use-dynamic-prompts` is enabled) | | |
| `use-dynamic-prompts` | Fetch latest prompt from Usable API instead of using static file | | `false` |
| `prompt-fragment-id` | Usable fragment UUID to use as prompt (required when `use-dynamic-prompts` is `true`) | ✓ (with dynamic prompts) | |
| `workspace-id` | Usable workspace UUID (required - used to fetch MCP system prompt) | ✓ | |
| `merge-custom-prompt` | Merge fetched Usable prompt with custom `prompt-file` (only when both are provided) | | `true` |
| `gemini-model` | Gemini model to use (`gemini-2.5-flash`, `gemini-2.0-flash`, `gemini-2.5-pro`) | | `gemini-2.5-flash` |
| `service-account-key-secret` | Secret name for service account key | | `GEMINI_SERVICE_ACCOUNT_KEY` |
| `mcp-server-url` | Usable MCP server URL | | `https://usable.dev/api/mcp` |
| `mcp-token-secret` | Secret name for Usable API token | | `USABLE_API_TOKEN` |
| `fail-on-critical` | Fail build on critical violations | | `true` |
| `comment-mode` | PR comment behavior (`update`/`new`/`none`) | | `update` |
| `comment-title` | Title for PR comment (for multi-stage validation) | | `Automated Standards Validation` |
| `artifact-retention-days` | Days to retain reports | | `30` |
| `max-retries` | Maximum retry attempts | | `2` |
| `timeout-minutes` | Maximum execution time in minutes | | `15` |
| `base-ref` | Base reference for diff comparison. Useful for release-please branches to compare against last release tag instead of base branch. | | PR base branch |
| `head-ref` | Head reference for diff comparison | | PR head branch |
| `allow-web-fetch` | Allow AI to use web_fetch tool for external resources (security consideration) | | `false` |

> **Note**: You must set the `USABLE_API_TOKEN` secret (or the custom secret name specified in `mcp-token-secret`). Usable MCP integration is required for this action.

### 🧠 System Prompts (Automatic)

The action **automatically** includes system prompts to ensure high-quality validations. The final prompt is assembled in this order:

1. **Action System Prompt** (hardcoded in `system-prompt.md`)
   - Critical guidelines (no hallucination, verify file contents)
   - Output format requirements
   - Severity definitions
   - Usable MCP integration instructions

2. **Workspace MCP System Prompt** (fetched from Usable API)
   - Your workspace-specific Usable MCP guidelines
   - Fetched from `/api/workspaces/{workspace-id}/mcp-system-prompt`
   - Defines how to search and use your knowledge base

3. **User Prompt** (your validation rules)
   - Repository-specific validation criteria
   - Can be a static file or dynamic from Usable

This three-layer approach ensures:

- ✅ Consistent validation behavior across all repositories
- ✅ Proper Usable MCP integration
- ✅ Accurate, hallucination-free reports
- ✅ Flexibility for repo-specific rules

### 🚀 Dynamic Prompts

Instead of maintaining static prompt files, you can now fetch prompts dynamically from your Usable workspace. This ensures you're always using the latest validation standards without manual updates.

**Benefits:**

- ✅ Always use the latest validation best practices
- ✅ Reduced setup complexity - no prompt file needed
- ✅ Automatic updates when your team's standards evolve
- ✅ Centralized prompt management in Usable

**How it works:**

1. Enable `use-dynamic-prompts: true`
2. Provide the `prompt-fragment-id` with your Usable fragment UUID
3. The action fetches that specific prompt from your Usable workspace
4. Automatically merges with system prompts (action + MCP)

**Examples:**

```yaml
# Dynamic user prompt from Usable
- uses: flowcore/usable-pr-validator@latest
  with:
    use-dynamic-prompts: true
    prompt-fragment-id: 'user-prompt-uuid'
    workspace-id: 'your-workspace-uuid'
  env:
    GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
    USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}

# Static user prompt file (most common)
- uses: flowcore/usable-pr-validator@latest
  with:
    prompt-file: '.github/prompts/pr-validation.md'
    workspace-id: 'your-workspace-uuid'
  env:
    GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
    USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
```

### Outputs

| Output | Description |
|--------|-------------|
| `validation-status` | Result: `passed` or `failed` |
| `validation-passed` | Boolean: `true` or `false` |
| `critical-issues` | Count of critical violations |
| `report-artifact-name` | Name of report artifact |

## 🎯 Usage Examples

### Minimal Setup

```yaml
- uses: flowcore/usable-pr-validator@latest
  with:
    prompt-file: '.github/prompts/validate.md'
    workspace-id: 'your-workspace-uuid'
  env:
    GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
    USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
```

### With Custom MCP Server

```yaml
- uses: flowcore/usable-pr-validator@latest
  with:
    prompt-file: '.github/prompts/validate.md'
    workspace-id: 'your-workspace-uuid'
    mcp-server-url: 'https://your-custom-mcp.com/api/mcp'
    mcp-token-secret: 'YOUR_CUSTOM_TOKEN'
  env:
    GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
    YOUR_CUSTOM_TOKEN: ${{ secrets.YOUR_MCP_TOKEN }}
```

### Advanced Configuration

```yaml
- uses: flowcore/usable-pr-validator@latest
  with:
    prompt-file: '.github/validation/standards.md'
    workspace-id: 'your-workspace-uuid'
    gemini-model: 'gemini-2.5-pro'
    service-account-key-secret: 'MY_GEMINI_KEY'
    mcp-server-url: 'https://confluence.company.com/api/mcp'
    mcp-token-secret: 'CONFLUENCE_TOKEN'
    fail-on-critical: true
    comment-mode: 'update'
    artifact-retention-days: 90
    max-retries: 3
  env:
    MY_GEMINI_KEY: ${{ secrets.GOOGLE_AI_KEY }}
    CONFLUENCE_TOKEN: ${{ secrets.CONF_API_TOKEN }}
```

### Multiple Validation Stages

Use `comment-title` to create separate PR comments for each validation stage:

```yaml
jobs:
  validate-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: flowcore/usable-pr-validator@latest
        with:
          prompt-file: '.github/prompts/backend-standards.md'
          workspace-id: 'your-workspace-uuid'
          comment-title: 'Backend Validation'  # Creates unique comment
        env:
          GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
          USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
  
  validate-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: flowcore/usable-pr-validator@latest
        with:
          prompt-file: '.github/prompts/frontend-standards.md'
          workspace-id: 'your-workspace-uuid'
          comment-title: 'Frontend Validation'  # Creates unique comment
        env:
          GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
          USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
```

> **Note**: Each `comment-title` creates a separate PR comment that updates independently. Artifacts are also uniquely named based on the title.

### Release-Please Integration

Validate all changes since the last release for release-please PRs:

```yaml
name: PR Validation

on:
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      # Determine base reference for release-please branches
      - name: Get base reference
        id: base-ref
        run: |
          if [[ "${{ github.head_ref }}" == release-please--* ]]; then
            # For release-please branches, compare against last release tag
            LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "${{ github.event.pull_request.base.ref }}")
            echo "ref=${LAST_TAG}" >> $GITHUB_OUTPUT
            echo "Comparing against last release: ${LAST_TAG}"
          else
            # For regular PRs, use base branch
            echo "ref=${{ github.event.pull_request.base.ref }}" >> $GITHUB_OUTPUT
            echo "Comparing against base branch: ${{ github.event.pull_request.base.ref }}"
          fi
      
      - uses: flowcore/usable-pr-validator@latest
        with:
          prompt-file: '.github/prompts/pr-validation.md'
          workspace-id: 'your-workspace-uuid'
          base-ref: ${{ steps.base-ref.outputs.ref }}  # Custom base reference
        env:
          GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
          USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
```

> **Tip**: This ensures release-please PRs validate all accumulated changes since the previous release, not just the most recent commit.

## 📝 Prompt Engineering

### Best Practices

1. **Clear Output Format**: Always specify exact markdown structure
2. **Suppress Preamble**: Explicitly instruct to start with report header
3. **Context Limits**: Remind AI not to output fetched content or logs
4. **Severity Levels**: Define clear criteria for Critical/Important/Suggestion
5. **Examples**: Include good/bad patterns in prompt

### Placeholder Variables

Available in your prompt file:

- `{{PR_CONTEXT}}` - Full PR context (number, title, description, URL)
- `{{BASE_BRANCH}}` - Target branch (e.g., `main`)
- `{{HEAD_BRANCH}}` - Source branch (e.g., `feature/new-thing`)
- `{{PR_TITLE}}` - Just the PR title
- `{{PR_DESCRIPTION}}` - Just the PR description
- `{{PR_NUMBER}}` - Just the PR number
- `{{PR_URL}}` - Direct link to PR
- `{{PR_AUTHOR}}` - GitHub username
- `{{PR_LABELS}}` - Comma-separated labels

### Report Structure

Your prompt should instruct the AI to output this structure:

```markdown
# PR Validation Report

## Summary
[Brief overview of findings]

## Critical Violations ❌
[Must-fix issues - build fails if present]

## Important Issues ⚠️
[Should-fix issues - build passes but flagged]

## Suggestions ℹ️
[Nice-to-have improvements]

## Validation Outcome
- **Status**: PASS ✅ | FAIL ❌
- **Critical Issues**: [count]
- **Important Issues**: [count]
- **Suggestions**: [count]
```

## 🔌 Usable Integration (Required)

### What is Usable?

Usable is a team knowledge base and memory system that stores your:

- Coding standards and conventions
- Architecture patterns and decisions
- Security requirements and best practices
- Project-specific documentation

**This action requires Usable** and connects to your Usable workspace via MCP (Model Context Protocol) to validate PRs against your living documentation. The integration is always enabled and provides the AI with access to your team's knowledge base.

### Setup

1. **Get Your Usable API Token**
   - Go to [usable.dev](https://usable.dev)
   - Navigate to Settings → API Tokens
   - Create a new token with `fragments.read` permission

2. **Add GitHub Secrets**

   ```bash
   # In your repo: Settings → Secrets → Actions
   USABLE_API_TOKEN=your_usable_token_here
   GEMINI_SERVICE_ACCOUNT_KEY=base64_encoded_key_here
   ```

3. **Configure Workflow**

  ```yaml
  - uses: flowcore/usable-pr-validator@latest
    with:
      prompt-file: '.github/prompts/pr-validation.md'
      workspace-id: 'your-workspace-uuid'
    env:
      GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
      USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
  ```

   > **Note**: Usable MCP integration is always enabled and uses `https://usable.dev/api/mcp` by default. You can customize the server URL with the `mcp-server-url` input if needed.

1. **Update Prompt to Use Usable**

   ```markdown
   ### Fetch Standards from Usable
   
   Use agentic-search-fragments to find relevant standards:
   - Coding standards for {{BASE_BRANCH}}
   - Architecture patterns
   - Security requirements
   - repo:your-repo-name tag
   
   Use get-memory-fragment-content for full details.
   ```

## 💬 Comment-Triggered Revalidation

**⚡ 2-Minute Setup** - Add comment-triggered validation to any repository!

### @usable Mentions

Trigger revalidations and approve deviations by commenting on a PR with `@usable`:

```text
@usable This PR intentionally uses console.log in debug utilities.
These files are specifically for debugging and need console output.
```

**What Happens**:

1. ✅ The action automatically triggers a revalidation
2. 📝 Your comment is passed to the AI validator
3. 🧠 The AI can:
   - **Understand the context** you've provided
   - **Approve deviations** from standards
   - **Document the decision** by creating a fragment in Usable
   - **Link the fragment** in the validation report
4. 📊 A new validation report is posted with the override applied

### Setting Up Comment Revalidation

Create `.github/workflows/comment-revalidation.yml`:

```yaml
name: Comment Revalidation

on:
  issue_comment:
    types: [created]

jobs:
  revalidate:
    # Only run if comment is on a PR and mentions @usable
    if: |
      github.event.issue.pull_request &&
      contains(github.event.comment.body, '@usable')
    
    # Use the reusable workflow - it handles everything!
    uses: flowcore/usable-pr-validator/.github/workflows/comment-revalidation.yml@v1
    with:
      workspace-id: 'your-workspace-uuid'  # REQUIRED
      prompt-file: '.github/prompts/pr-validation.md'  # Optional
      # Customize as needed:
      # use-dynamic-prompts: true
      # prompt-fragment-id: 'fragment-uuid'
      # gemini-model: 'gemini-2.5-flash'
      # comment-title: '🔄 Custom Title'
      # fail-on-critical: false
    secrets:
      GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
      USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
    permissions:
      contents: read
      pull-requests: write
```

**That's it!** Just 15 lines and you're done. The reusable workflow handles:

- ✅ Extracting PR details
- ✅ Checking out the correct commit
- ✅ Determining base ref (branch vs tag)
- ✅ Running validation with override context
- ✅ Posting results as a comment
- ✅ Adding reaction emoji to acknowledge

> **Tip**: Copy `templates/comment-revalidation-workflow.yml` for a ready-to-use template

### How It Works

#### Example: Approving a Deviation

1. **PR has a violation**: Validator flags `console.log` usage

2. **Developer comments**:

   ```text
   @usable This is intentional. The debug utility needs console output 
   for troubleshooting production issues. Only used in /debug/ directory.
   ```

3. **Validator understands and documents**:
   - Creates a fragment in Usable titled "Approved Deviation: console.log in debug utilities"
   - Includes justification, conditions, PR link, and approver
   - Tags it as `deviation`, `approved`, `repo:your-repo`

4. **Report shows**:

   ```markdown
   ## Override Applied
   
   A deviation from standards has been approved and documented:
   
   - **Deviation**: console.log usage in debug utilities
   - **Justification**: Required for production troubleshooting
   - **Documentation**: Fragment created - "Approved Deviation: console.log in debug utilities" (ID: abc-123)
   - **Approved by**: @developer
   
   This deviation has been recorded in the knowledge base for future reference.
   ```

**Use Cases**:

- ✅ **Approve Deviations**: "This violation is acceptable because..."
- 🎯 **Focus Validation**: "@usable Focus on security issues only"
- 💡 **Provide Context**: "@usable This API change was approved by the architecture team"
- 🔄 **Re-run After Fixes**: "@usable Please revalidate now that I've fixed the issues"

**Benefits**:

- 📚 **Knowledge Base Grows**: Approved deviations are automatically documented
- 🔗 **Traceability**: Every deviation links back to the approving PR and person
- 🤝 **Team Communication**: Decisions are visible to everyone
- 🚀 **No Manual Work**: AI handles documentation automatically

## 🔒 Security

### Secret Handling

- Service account keys are base64-decoded to `/tmp` with `600` permissions
- Temporary files automatically cleaned up in `always()` block
- Never logged or exposed in outputs
- Use GitHub encrypted secrets for storage

### Permissions Required

```yaml
permissions:
  contents: read        # Read repository code
  pull-requests: write  # Post comments
```

### Security Best Practices

1. Use Vertex AI (recommended) over API keys
2. Rotate service account keys regularly
3. Use least-privilege service accounts
4. Enable audit logging in Google Cloud
5. Review validation prompts for sensitive data
6. **Keep `allow-web-fetch` disabled** (default) unless you specifically need it

### Web Fetch Security

The `allow-web-fetch` input controls whether the AI can download external resources during validation.

**Default: `false` (DISABLED)** - Recommended for most use cases

- ✅ **When to keep it disabled (default)**:
  - Standard PR validation using only your codebase and Usable knowledge base
  - Security-sensitive environments
  - When you want to ensure validation is fully reproducible
  - When you don't need external documentation or references

- ⚠️ **When you might enable it**:
  - Validating against external API documentation
  - Checking compliance with published standards (e.g., OWASP, RFC specs)
  - Verifying links in documentation PRs
  - Fetching external schema definitions

**Security implications when enabled**:

- AI can make HTTP requests to arbitrary URLs
- Could potentially expose internal URLs if mentioned in PR
- May introduce non-deterministic validation results
- Consider network egress policies and firewall rules

**Example of enabling**:

```yaml
- uses: flowcore/usable-pr-validator@latest
  with:
    prompt-file: '.github/prompts/validate-api-docs.md'
    allow-web-fetch: true  # Only enable when needed
  env:
    GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
    USABLE_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
```

## 🐛 Troubleshooting

### No Output from Gemini CLI

**Symptom**: GitHub Action runs but shows no Gemini output or errors

**Possible Causes**:

- Gemini CLI failing silently
- Output buffering issues
- Git diff failures preventing AI from analyzing changes

**Solutions**:

1. **Check the Git Diff Setup section** in action logs:

```
🔍 Verifying Git Diff Setup
✅ Base ref available: origin/main
✅ Head ref available: origin/feature-branch
✅ Three-dot diff works: origin/main...origin/feature-branch
```

2. **Look for Gemini CLI output** in the logs:

```
🤖 Running Gemini CLI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Model: gemini-2.5-flash
Prompt size: XXXX bytes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

3. **Check for error details** in collapsed groups:

- Look for "❌ Error Details" group
- Check both STDERR and STDOUT output
- Review exit codes

4. **Verify git refs are properly fetched**:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0  # Important: fetch full history
```

5. **Use the diagnostic script locally**:

```bash
# Clone the repo and run
./scripts/test-git-diff.sh main feature-branch
```

### Git Diff Not Working

**Symptom**: Error messages like "revisions or paths not found" or AI reports inability to analyze changes

**Root Cause**: Git refs not properly fetched in GitHub Actions environment

**Automated Fix** (already implemented in v1.3.1+):

- Enhanced git setup with retry logic for both base and head refs
- Multiple ref format attempts (branch, tag, explicit refspec)
- Pre-flight validation that tests git diff before AI starts

**Manual Verification**:

```bash
# Run diagnostic script
./scripts/test-git-diff.sh <base-branch> <head-branch>

# Expected output:
# ✅ Base ref available: origin/main
# ✅ Head ref available: origin/feature
# ✅ Three-dot diff works
# 📊 5 files changed
```

**Common Mistake - Detached HEAD**:

If you're checking out with a specific SHA, this creates a detached HEAD state that breaks diff operations:

```yaml
# ❌ WRONG - Creates detached HEAD
- uses: actions/checkout@v4
  with:
    ref: ${{ github.event.pull_request.head.sha }}
    fetch-depth: 0

# ✅ CORRECT - Let checkout handle the ref automatically
- uses: actions/checkout@v4
  with:
    fetch-depth: 0  # This is all you need for PRs
```

**If you MUST use a specific ref**:

```yaml
# Option 1: Don't specify ref for PR workflows
- uses: actions/checkout@v4
  with:
    fetch-depth: 0

# Option 2: Explicitly fetch both refs after checkout
- uses: actions/checkout@v4
  with:
    ref: ${{ github.event.pull_request.head.sha }}
    fetch-depth: 0

- name: Fetch branch refs
  run: |
    git fetch origin ${{ github.event.pull_request.base.ref }}:refs/remotes/origin/${{ github.event.pull_request.base.ref }}
    git fetch origin ${{ github.event.pull_request.head.ref }}:refs/remotes/origin/${{ github.event.pull_request.head.ref }}
```

### MCP Tools Not Available

**Symptom**: Error messages like `Tool "search_memory_fragments" not found in registry` or AI sees wrong tools (`search_file_content`, `read_many_files` instead of Usable Memory tools)

**Root Cause**: MCP server not receiving workspace-id context, so it returns generic tools instead of Usable-specific memory tools

**Solution** (Fixed in v1.6.0+):

The action now automatically passes `workspace-id` to the MCP server via the `x-workspace-id` header. Ensure you're using the latest version:

```yaml
- uses: flowcore-io/usable-pr-validator@v1.6.0  # or @latest
  with:
    workspace-id: '60c10ca2-4115-4c1a-b6d7-04ac39fd3938'  # Required!
```

**If using older versions**, update to v1.6.0+ or manually verify:

1. `workspace-id` input is provided in your workflow
2. Action passes `WORKSPACE_ID` environment variable to MCP setup
3. MCP settings include `x-workspace-id` header in configuration

**Expected MCP tools** when working correctly:

- `agentic-search-fragments`
- `search-memory-fragments`
- `get-memory-fragment-content`
- `explore-workspace-graph`
- `create-memory-fragment`
- `update-memory-fragment`

### Validation Fails Immediately

**Symptom**: Action fails before running Gemini

**Causes**:

- Prompt file not found
- Missing required secrets
- Invalid MCP configuration

**Solution**:

```bash
# Check prompt file exists
ls -la .github/prompts/

# Verify secrets are set
# Go to repo Settings → Secrets → Actions
```

### Report Not Extracted

**Symptom**: Warning about report extraction

**Cause**: AI didn't follow output format instructions

**Solution**: Strengthen prompt instructions:

```markdown
## CRITICAL OUTPUT INSTRUCTION
**YOU MUST START WITH:** `# PR Validation Report`
DO NOT include thinking process or explanations!
```

### API Rate Limit Errors

**Symptom**: 429 errors from Gemini API

**Solution**:

- Use Vertex AI (higher limits)
- Increase `max-retries`
- Add exponential backoff
- Check Google Cloud quotas

### MCP Connection Failures

**Symptom**: Can't connect to MCP server

**Solutions**:

```yaml
# 1. Verify URL is correct
mcp-server-url: 'https://correct-url.com/api/mcp'

# 2. Check token is valid
# Ensure MCP_API_TOKEN secret is set

# 3. Test connectivity
curl -H "Authorization: Bearer $TOKEN" $MCP_URL
```

## 📊 Cost Estimation

### Google Gemini Pricing (Vertex AI)

| Model | Input (per 1M tokens) | Output (per 1M tokens) | Typical PR Cost |
|-------|----------------------|----------------------|----------------|
| gemini-2.5-flash | $0.075 | $0.30 | $0.01-0.03 |
| gemini-2.0-flash | $0.10 | $0.40 | $0.02-0.05 |
| gemini-2.5-pro | $1.25 | $5.00 | $0.25-1.00 |

**Estimate**: ~$0.01-0.05 per PR with gemini-2.5-flash (recommended)

### MCP Costs

MCP server costs vary by provider:

- **Usable**: Check pricing at usable.dev
- **Self-hosted**: Server infrastructure costs
- **Confluence**: Included in license

## 🔖 Versioning

This action follows [Semantic Versioning](https://semver.org/) and uses automated releases via [release-please](https://github.com/google-github-actions/release-please-action).

### Using Specific Versions

```yaml
# Latest stable release (recommended)
- uses: flowcore/usable-pr-validator@latest

# Specific version (pinned)
- uses: flowcore/usable-pr-validator@v1.0.0

# Latest commit on main (not recommended for production)
- uses: flowcore/usable-pr-validator@main
```

### Version Strategy

- **Major (v1.x.x → v2.x.x)**: Breaking changes requiring user action
- **Minor (v1.0.x → v1.1.x)**: New features, backward compatible
- **Patch (v1.0.0 → v1.0.1)**: Bug fixes, backward compatible

We recommend using `@latest` to automatically receive the newest stable release.

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

All commits must follow [Conventional Commits](https://www.conventionalcommits.org/) for automated releases:

- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation
- `feat!:` or `BREAKING CHANGE:` for breaking changes

### Development Setup

```bash
git clone https://github.com/flowcore/usable-pr-validator.git
cd usable-pr-validator

# Test locally (requires act)
act pull_request -s GEMINI_SERVICE_ACCOUNT_KEY="$(cat key.json | base64)"
```

## 📜 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- Google Gemini for AI capabilities
- Model Context Protocol (MCP) community
- GitHub Actions ecosystem

## 📞 Support

- 🐛 [Report a bug](https://github.com/flowcore/usable-pr-validator/issues)
- 💡 [Request a feature](https://github.com/flowcore/usable-pr-validator/issues)
- 💬 [Discussions](https://github.com/flowcore/usable-pr-validator/discussions)

Made with ❤️ by [Flowcore](https://flowcore.io)
