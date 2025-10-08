# PR Validation Instructions

## CRITICAL OUTPUT INSTRUCTION
**YOU MUST OUTPUT ONLY THE VALIDATION REPORT - NOTHING ELSE!**

Do NOT include:
- ❌ Thinking process
- ❌ Standards content fetched
- ❌ Git outputs
- ❌ Tool execution logs

**START YOUR OUTPUT DIRECTLY WITH:** `# PR Validation Report`

## PR Context

{{PR_CONTEXT}}

## Your Task

Analyze the changes in this PR and validate against project standards.

### Get PR Changes

Run the following command to see what changed:
```bash
# Compare base ref (branch or tag) with HEAD
# If BASE_BRANCH is a tag, use it directly; if it's a branch, try origin/ prefix
git diff {{BASE_BRANCH}}...HEAD 2>/dev/null || git diff origin/{{BASE_BRANCH}}...HEAD
```

You can also see the list of changed files:
```bash
git diff --name-only {{BASE_BRANCH}}...HEAD 2>/dev/null || git diff --name-only origin/{{BASE_BRANCH}}...HEAD
```

### Validation Criteria

Check for:

**Critical Violations ❌** (Must fix - causes build failure):
- Security vulnerabilities or exposed secrets
- Breaking API changes without migration path
- Code that will cause runtime errors
- Violations of core architectural patterns
- Missing required tests for new features

**Important Issues ⚠️** (Should fix - doesn't block merge):
- Code style violations
- Missing documentation
- Performance concerns
- Incomplete error handling
- TODO comments without tracking tickets

**Suggestions ℹ️** (Nice to have):
- Code optimization opportunities
- Better naming conventions
- Additional test coverage
- Refactoring opportunities

## Output Format

Output ONLY the following markdown structure:

```markdown
# PR Validation Report

## Summary
[Brief 2-3 sentence overview of the PR and validation outcome]

## Critical Violations ❌
[List critical issues that MUST be fixed. Leave empty if none found]

- [ ] **[Issue Title]**: Description of the issue and why it's critical
  - File: `path/to/file.ext`
  - Line: XX
  - Recommendation: How to fix it

## Important Issues ⚠️
[List important issues that SHOULD be fixed. Leave empty if none found]

- [ ] **[Issue Title]**: Description of the issue
  - File: `path/to/file.ext`
  - Recommendation: How to improve it

## Suggestions ℹ️
[List optional improvements. Leave empty if none]

- **[Suggestion Title]**: Description of the suggestion

## Validation Outcome

- **Status**: PASS ✅ | FAIL ❌
- **Critical Issues**: [count]
- **Important Issues**: [count]
- **Suggestions**: [count]

[If PASS: Brief encouraging message]
[If FAIL: Brief summary of what needs to be fixed]
```

Remember: Output ONLY the report above, starting with `# PR Validation Report`. No preamble, no explanations, just the report.
