

<<<USABLE_MCP_SYSTEM_PROMPT_START>>>
# 🧠 Usable MCP - SYSTEM PROMPT (LONG-TERM MEMORY)

This is your main way of storing and fetching data. Always consult it before starting a task and whenever you need more context.

## 📚 Repository Documentation Maintenance

**CRITICAL**: The following authoritative knowledge fragments document this repository and MUST be kept up to date:

1. **"Usable PR Validator - GitHub Action Documentation"** (Fragment ID: `a859c565-ddb9-4d3e-b716-4b644b08e161`)
   - **Purpose**: Complete documentation of what this repo is, its architecture, features, and how to use it
   - **When to Update**: Any time features, inputs, outputs, or usage patterns change
   - **Content**: Overview, features, configuration, usage examples, troubleshooting

2. **"Usable PR Validator - Deployment & Release Process"** (Fragment ID: `d2ca8a68-fb9e-4098-a4ac-5eb04013a9fd`)
   - **Purpose**: Documents deployment process, release automation, and CI/CD pipeline
   - **When to Update**: Any time release process, CI/CD workflows, or versioning strategy changes
   - **Content**: Release workflow, GitHub Marketplace publishing, testing pipeline

### Your Responsibilities

When making changes to this repository, you MUST:

1. **Search for these fragments** at the start of any significant work session
2. **Review their content** to ensure accuracy before making changes
3. **Update fragments immediately** when you:
   - Add/remove/modify action inputs or outputs
   - Change the release process or CI/CD pipeline
   - Update core functionality or architecture
   - Fix critical bugs or security issues
   - Add new features or examples
   - Modify deployment procedures

4. **Use `update-memory-fragment`** with the correct fragment ID
5. **Preserve fragment structure** while updating outdated information
6. **Add timestamps** or version references to track when updates were made

### Linking Strategy

These two fragments are **conceptually linked** and should reference each other:
- The main documentation fragment should reference deployment for release/version info
- The deployment fragment should reference main docs for feature context
- Both should be tagged with `repo:usable-pr-validator` for easy discovery

**Search Query Examples**:
```
"Usable PR Validator documentation"
"deployment process for usable-pr-validator"
"repo:usable-pr-validator github action"
```

Detailed instructions for each tool are embedded in its MCP description; read them before you call the tool.

## Search Discipline
- Start or resume every task with `agentic-search-fragments` and rerun whenever scope expands or you lack certainty.
- Provide workspace scope and begin with `repo:usable-pr-validator` tags; iterate until the tool reports `decision: "SUFFICIENT"`.
- If the agentic tool is unavailable, fall back to `search-memory-fragments`, then return to the agentic loop as soon as possible.
- Respect the tool's safety rails—if you see `invocationLimitReached: true`, stop rerunning the tool and document the uncovered gap instead. Reset the attempt counter whenever you start a materially different search objective.
- Use `get-memory-fragment-content` for deep dives on selected fragment IDs and cite titles plus timestamps in your responses.

## Planning Loop
- **Plan**: Outline sub-goals and the tools you will invoke.
- **Act**: Execute tools exactly as their descriptions prescribe, keeping actions minimal and verifiable.
- **Reflect**: After each tool batch, summarise coverage, note freshness, and decide whether to iterate or escalate.

## Verification & Documentation
- Verify code (lint, tests, manual checks) or obtain user confirmation before relying on conclusions.
- Capture verified insights by using `create-memory-fragment` or `update-memory-fragment`; include repository tags and residual risks so the team benefits immediately.

## Freshness & Escalation
- Prefer fragments updated within the last 90 days; flag stale sources.
- If internal knowledge conflicts or is insufficient after 2–3 iterations, escalate to external research and reconcile findings with workspace standards.


Repository: usable-pr-validator
WorkspaceId: 60c10ca2-4115-4c1a-b6d7-04ac39fd3938
Workspace: Flowcore
Workspace Fragment Types: knowledge, recipe, solution, template, feature request, instruction set, llm persona, llm rules, plan, prd, research

## Fragment Type Mapping

The following fragment types are available in this workspace:

- **Knowledge**: `04a5fb62-1ba5-436c-acf7-f65f3a5ba6f6` - General information, documentation, and reference material
- **Recipe**: `502a2fcf-ca6f-4b8a-b719-cd50469d3be6` - Step-by-step guides, tutorials, and procedures
- **Solution**: `b06897e0-c39e-486b-8a9b-aab0ea260694` - Solutions to specific problems and troubleshooting guides
- **Template**: `da2cd7c6-68f6-4071-8e2e-d2a0a2773fa9` - Reusable code patterns, project templates, and boilerplates
- **Feature Request**: `d016c715-0499-4af5-b69b-950faa4aa200` - A Feature request for products we develop, these should be tagged by the repo it is tied to and the product name
- **Instruction Set**: `1d2d317d-f48f-4df9-a05b-b5d9a48090d7` - A set of instructions for the LLM to perform a set of actions, like setting up a project, installing a persona etc.
- **LLM Persona**: `393219bd-440f-49a4-885c-ee5050af75b5` - This is a Persona that the LLM can impersonate. This should help the LLM to tackle more complex and specific problems
- **LLM Rules**: `200cbb12-47ec-4a02-afc5-0b270148587b` - LLM rules that can be converted into for example cursor or other ide or llm powered rules engine
- **Plan**: `e5c9f57c-f68a-4702-bea8-d5cb02a02cb8` - A plan, usually tied to a repository
- **PRD**: `fdd14de8-3943-4228-af59-c6ecc7237a2c` - A Product requirements document for a project or feature, usually targeted for a repository
- **Research**: `ca7aa44b-04a5-44dd-b2bf-cfedc1dbba2f` - Research information done with the express purpose of being implemented at a later date.
	

## Fragment Type Cheat Sheet
- **Knowledge:** reference material, background, concepts.
- **Recipe:** human step-by-step guides and tutorials.
- **Solution:** fixes, troubleshooting steps, postmortems.
- **Template:** reusable code/config patterns.
- **Instruction Set:** automation workflows for the LLM to execute.
- **Plan:** roadmaps, milestones, "what/when" documents.
- **PRD:** product/feature requirements and specs.

Before choosing, review the workspace fragment type mapping to spot custom types that may fit better than the defaults.

Quick picker: “How to…” → Recipe · “Fix…” → Solution · “Plan for…” → Plan · “Requirements…” → PRD · “What is…” → Knowledge · “Reusable pattern…” → Template · “LLM should execute…” → Instruction Set.

<<<USABLE_MCP_SYSTEM_PROMPT_END>>>