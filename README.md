# 🤖 AI-Powered PR Validator

> Validate Pull Requests against custom standards using Google Gemini AI and optional MCP knowledge base integration

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-AI--Powered%20PR%20Validator-blue?logo=github)](https://github.com/marketplace/actions/ai-powered-pr-validator)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## ✨ Features

- 🧠 **AI-Powered Validation**: Uses Google Gemini to understand context and architectural patterns
- 📚 **Knowledge Base Integration**: Optional MCP server support for living documentation
- ⚙️ **Highly Configurable**: Customizable prompts, severity levels, and validation rules
- 🔄 **Reliable**: Automatic retry logic with exponential backoff for API failures
- 💬 **Smart PR Comments**: Updates existing comments to avoid spam
- 📊 **Detailed Reports**: Structured validation reports as artifacts and PR comments
- 🔒 **Secure**: Proper secret handling with automatic cleanup

## 🚀 Quick Start (5 Minutes)

### Prerequisites

1. A Google Cloud project with Vertex AI API enabled
2. A service account key with Vertex AI permissions
3. GitHub repository with pull requests

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
```

### Step 2: Add GitHub Secrets

Go to your repository Settings → Secrets → Actions and add:

- `GEMINI_SERVICE_ACCOUNT_KEY`: Base64-encoded service account JSON key
  ```bash
  cat service-account.json | base64
  ```

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
      
      - uses: flowcore/ai-pr-validator@v1
        with:
          prompt-file: '.github/prompts/pr-validation.md'
        env:
          GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
```

That's it! Your PRs will now be validated automatically. 🎉

## 📖 Configuration

### Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `prompt-file` | Path to validation prompt markdown file | ✅ Yes | - |
| `gemini-model` | Gemini model to use | No | `gemini-2.5-flash` |
| `service-account-key-secret` | Secret name for service account key | No | `GEMINI_SERVICE_ACCOUNT_KEY` |
| `mcp-enabled` | Enable MCP server integration | No | `false` |
| `mcp-server-url` | HTTP URL of MCP server | No | - |
| `mcp-token-secret` | Secret name for MCP token | No | `MCP_API_TOKEN` |
| `fail-on-critical` | Fail build on critical violations | No | `true` |
| `comment-mode` | PR comment behavior (`update`/`new`/`none`) | No | `update` |
| `artifact-retention-days` | Days to retain reports | No | `30` |
| `max-retries` | Maximum retry attempts | No | `2` |
| `timeout-minutes` | Maximum execution time | No | `15` |

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
- uses: flowcore/ai-pr-validator@v1
  with:
    prompt-file: '.github/prompts/validate.md'
  env:
    GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
```

### With MCP Knowledge Base

```yaml
- uses: flowcore/ai-pr-validator@v1
  with:
    prompt-file: '.github/prompts/validate.md'
    mcp-enabled: true
    mcp-server-url: 'https://usable.dev/api/mcp'
  env:
    GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
    MCP_API_TOKEN: ${{ secrets.USABLE_API_TOKEN }}
```

### Advanced Configuration

```yaml
- uses: flowcore/ai-pr-validator@v1
  with:
    prompt-file: '.github/validation/standards.md'
    gemini-model: 'gemini-2.5-pro'
    service-account-key-secret: 'MY_GEMINI_KEY'
    mcp-enabled: true
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

```yaml
jobs:
  validate-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: flowcore/ai-pr-validator@v1
        with:
          prompt-file: '.github/prompts/backend-standards.md'
        env:
          GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
  
  validate-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: flowcore/ai-pr-validator@v1
        with:
          prompt-file: '.github/prompts/frontend-standards.md'
        env:
          GEMINI_SERVICE_ACCOUNT_KEY: ${{ secrets.GEMINI_SERVICE_ACCOUNT_KEY }}
```

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

## 🔌 MCP Integration

### What is MCP?

Model Context Protocol (MCP) allows AI to access external knowledge bases like:
- Usable (usable.dev)
- Internal wikis (Confluence, Notion)
- Custom documentation systems

### Setup

1. **Get MCP Server URL and Token**
   - For Usable: https://usable.dev/api/mcp
   - For custom: Deploy your own MCP server

2. **Add Secrets**
   ```
   MCP_API_TOKEN=your_token_here
   ```

3. **Enable in Workflow**
   ```yaml
   with:
     mcp-enabled: true
     mcp-server-url: 'https://usable.dev/api/mcp'
   ```

4. **Update Prompt to Use MCP**
   ```markdown
   ### Fetch Standards from Knowledge Base
   
   Use agentic-search-fragments to find:
   - Coding standards for {{BASE_BRANCH}}
   - Architecture patterns
   - Security requirements
   
   Use get-memory-fragment-content for full details.
   ```

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

### Best Practices

1. Use Vertex AI (recommended) over API keys
2. Rotate service account keys regularly
3. Use least-privilege service accounts
4. Enable audit logging in Google Cloud
5. Review validation prompts for sensitive data

## 🐛 Troubleshooting

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

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
git clone https://github.com/flowcore/ai-pr-validator.git
cd ai-pr-validator

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

- 🐛 [Report a bug](https://github.com/flowcore/ai-pr-validator/issues)
- 💡 [Request a feature](https://github.com/flowcore/ai-pr-validator/issues)
- 💬 [Discussions](https://github.com/flowcore/ai-pr-validator/discussions)

---

Made with ❤️ by [Flowcore](https://flowcore.io)
