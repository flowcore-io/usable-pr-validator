# Contributing to Usable PR Validator

Thank you for your interest in contributing! 🎉

## Code of Conduct

Be respectful, inclusive, and constructive in all interactions.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/flowcore/usable-pr-validator/issues)
2. If not, create a new issue with:
   - Clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - Your environment (OS, GitHub Actions runner, etc.)
   - Relevant logs (redact any secrets!)

### Suggesting Features

1. Check [existing feature requests](https://github.com/flowcore/usable-pr-validator/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)
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
git clone https://github.com/YOUR_USERNAME/usable-pr-validator.git
cd usable-pr-validator

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

Releases are automated using [release-please](https://github.com/google-github-actions/release-please-action):

### How It Works

1. **Commit with conventional commits** to `main` branch
   - `feat:` triggers minor version bump (0.1.0 → 0.2.0)
   - `fix:` triggers patch version bump (0.1.0 → 0.1.1)
   - `feat!:` or `BREAKING CHANGE:` triggers major version bump (0.x.x → 1.0.0)

2. **Release-please creates/updates a release PR**
   - Automatically generates CHANGELOG.md
   - Updates version references
   - Groups commits by type
   - **PR is created automatically after commits are pushed to main**

3. **Merge the release PR**
   - Creates a GitHub release with tag (e.g., `v0.1.0`)
   - GitHub Marketplace **automatically** detects the tag and updates
   - Tag follows format: `v0.1.0`

### Initial Marketplace Setup (One-Time)

The action must be published to GitHub Marketplace initially:

1. Go to repository → Releases
2. Click "Draft a new release"
3. Create tag `v0.1.0` targeting `main` branch
4. Check "Publish this Action to the GitHub Marketplace"
5. Fill in required marketplace details
6. Publish release

**After initial setup**, all future releases via release-please automatically update the marketplace listing.

### Manual Release Steps

If needed, maintainers can manually:

1. Review the auto-generated release PR
2. Edit CHANGELOG.md if needed
3. Merge the release PR
4. GitHub Actions handles the rest

### Version Strategy

- **Major** (x.0.0): Breaking changes, requires user action
- **Minor** (1.x.0): New features, backward compatible
- **Patch** (1.0.x): Bug fixes, backward compatible

## Getting Help

- 💬 [Discussions](https://github.com/flowcore/usable-pr-validator/discussions)
- 🐛 [Issues](https://github.com/flowcore/usable-pr-validator/issues)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
