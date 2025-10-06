# Contributing to AI-Powered PR Validator

Thank you for your interest in contributing! 🎉

## Code of Conduct

Be respectful, inclusive, and constructive in all interactions.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/flowcore/ai-pr-validator/issues)
2. If not, create a new issue with:
   - Clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - Your environment (OS, GitHub Actions runner, etc.)
   - Relevant logs (redact any secrets!)

### Suggesting Features

1. Check [existing feature requests](https://github.com/flowcore/ai-pr-validator/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)
2. Create a new issue with:
   - Clear use case description
   - Proposed solution
   - Alternative solutions considered
   - Any breaking changes

### Submitting Pull Requests

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**:
   - Follow existing code style
   - Add comments for complex logic
   - Update documentation if needed

4. **Test your changes**:
   ```bash
   # Test the action locally using act
   act pull_request -s GEMINI_SERVICE_ACCOUNT_KEY="$(cat key.json | base64)"
   ```

5. **Commit with clear messages**:
   ```bash
   git commit -m "feat: add support for custom report templates"
   ```

6. **Push and create PR**:
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Fill out PR template** with:
   - Description of changes
   - Related issues
   - Testing performed
   - Screenshots (if UI changes)

## Development Setup

### Prerequisites

- Git
- Bash
- [act](https://github.com/nektos/act) for local testing
- Google Cloud service account for testing

### Local Testing

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/ai-pr-validator.git
cd ai-pr-validator

# Create a test PR in a repo
# Add secrets to test environment
export GEMINI_SERVICE_ACCOUNT_KEY="$(cat path/to/key.json | base64)"

# Run action locally
act pull_request
```

## Code Style

### Shell Scripts

- Use `set -euo pipefail` at the top
- Quote variables: `"$VAR"`
- Use functions for reusable logic
- Add comments for complex operations
- Use meaningful variable names

### GitHub Actions YAML

- Use descriptive step names
- Add comments for complex workflows
- Keep indentation consistent (2 spaces)
- Group related steps with `::group::`

### Documentation

- Use clear, concise language
- Include code examples
- Update README for new features
- Update CHANGELOG following [Keep a Changelog](https://keepachangelog.com/)

## Commit Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

[optional body]

[optional footer]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Examples**:
```
feat(mcp): add support for multiple MCP servers
fix(validation): handle empty PR descriptions correctly
docs(readme): add troubleshooting section
```

## Release Process

1. Update CHANGELOG.md
2. Update version in documentation
3. Create GitHub release with tag
4. Publish to GitHub Marketplace

## Getting Help

- 💬 [Discussions](https://github.com/flowcore/ai-pr-validator/discussions)
- 🐛 [Issues](https://github.com/flowcore/ai-pr-validator/issues)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
