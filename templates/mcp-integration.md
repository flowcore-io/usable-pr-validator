# PR Validation with Knowledge Base Integration

## CRITICAL OUTPUT INSTRUCTION
**YOU MUST OUTPUT ONLY THE VALIDATION REPORT - NOTHING ELSE!**

Do NOT include:
- ❌ Thinking process
- ❌ Standards content fetched from MCP
- ❌ Git outputs
- ❌ Tool execution logs
- ❌ MCP query results

**START YOUR OUTPUT DIRECTLY WITH:** `# PR Validation Report`

## PR Context

{{PR_CONTEXT}}

## Your Task

Analyze this PR against project standards stored in the knowledge base.

### Step 1: Fetch Project Standards from Knowledge Base

Use the MCP server tools to search for relevant standards:

```
agentic-search-fragments with query about:
- Project coding standards
- Architecture patterns
- Security requirements
- Testing requirements
- Documentation standards
```

Fetch full content of relevant standards using `get-memory-fragment-content`.

### Step 2: Get PR Changes

Run the following command to see what changed:
```bash
# Compare base ref (branch or tag) with HEAD
# If BASE_BRANCH is a tag, use it directly; if it's a branch, try origin/ prefix
git diff {{BASE_BRANCH}}...HEAD 2>/dev/null || git diff origin/{{BASE_BRANCH}}...HEAD
```

List changed files:
```bash
git diff --name-only {{BASE_BRANCH}}...HEAD 2>/dev/null || git diff --name-only origin/{{BASE_BRANCH}}...HEAD
```

### Step 3: Validate Against Standards

Compare the PR changes against the fetched standards. Check for:

**Critical Violations ❌** (Must fix):
- Violations of documented architectural patterns
- Security issues per security standards
- Breaking changes not following migration guidelines
- Missing required tests per testing standards
- Code that contradicts established patterns

**Important Issues ⚠️** (Should fix):
- Deviations from coding style guide
- Incomplete documentation per doc standards
- Missing error handling per error handling patterns
- Performance anti-patterns

**Suggestions ℹ️** (Nice to have):
- Opportunities to follow best practices better
- Additional patterns that could be applied
- Enhanced documentation opportunities

## Output Format

Output ONLY the validation report in this exact structure:

```markdown
# PR Validation Report

## Summary
[2-3 sentence overview: what changed, how it compares to standards, outcome]

## Standards Referenced
[List the key standards/patterns checked against from knowledge base]
- [Standard name from knowledge base]
- [Standard name from knowledge base]

## Critical Violations ❌
[List MUST-fix issues. Empty if none]

- [ ] **[Violation]**: Description
  - File: `path/to/file.ext`
  - Line: XX
  - Standard: [Which standard from KB]
  - Recommendation: [How to fix per standard]

## Important Issues ⚠️
[List SHOULD-fix issues. Empty if none]

- [ ] **[Issue]**: Description
  - File: `path/to/file.ext`
  - Standard: [Which standard from KB]
  - Recommendation: [How to improve]

## Suggestions ℹ️
[List optional improvements. Empty if none]

- **[Suggestion]**: Description and reference to relevant patterns

## Validation Outcome

- **Status**: PASS ✅ | FAIL ❌
- **Critical Issues**: [count]
- **Important Issues**: [count]
- **Suggestions**: [count]
- **Standards Checked**: [count of standards referenced]

[If PASS: Brief encouraging message]
[If FAIL: Brief summary with references to specific standards]
```

**IMPORTANT**: Do not include the standards content itself in the output. Only reference them by name and cite violations.

Remember: Output ONLY the report, starting with `# PR Validation Report`. No preamble!
