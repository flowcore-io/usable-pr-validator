# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0](https://github.com/flowcore-io/usable-pr-validator/compare/v1.6.0...v2.0.0) (2026-02-10)


### ⚠ BREAKING CHANGES

* enhance AI provider support and update documentation for OpenCode and Gemini integration

### Features

* enhance AI provider support and update documentation for OpenCode and Gemini integration ([206df6d](https://github.com/flowcore-io/usable-pr-validator/commit/206df6dc5d4a6242bf2b264fcc08a80e5185d932))


### Bug Fixes

* update default provider to OpenCode in setup and validation scripts ([d132742](https://github.com/flowcore-io/usable-pr-validator/commit/d1327426d3bbdd9352ac2092b5c4195e5dfac09a))

## [1.6.0](https://github.com/flowcore-io/usable-pr-validator/compare/v1.5.2...v1.6.0) (2025-10-24)


### Features

* **validation:** :sparkles: smart diff summary for scalable PR validation ([473e73b](https://github.com/flowcore-io/usable-pr-validator/commit/473e73b8ba2d60344f818262e1851cced11cb5ec))
* **validation:** add PR validation prompt for Next.js standards ([350b533](https://github.com/flowcore-io/usable-pr-validator/commit/350b53342d2cf42d92bc71bc08328c49b8518905))
* **validation:** add PR validation prompt for Next.js standards ([366afe4](https://github.com/flowcore-io/usable-pr-validator/commit/366afe4dac6c8388de70ab3b8d7c154cf586dc60))


### Bug Fixes

* **fetch-prompt:** improve handling of custom prompt file fallback ([99c6661](https://github.com/flowcore-io/usable-pr-validator/commit/99c66615d503626defaa623a817b7f2739f302c4))
* **scripts:** improve error handling and environment variable exports ([783f9f8](https://github.com/flowcore-io/usable-pr-validator/commit/783f9f82d7bacb5e901a34ccb4c510c2e1437438))
* **validation:** :bug: redirect status messages to stderr in prepare_prompt ([bbbf39c](https://github.com/flowcore-io/usable-pr-validator/commit/bbbf39cd4e9b5b79d2805d79faf2e20767bc04cf))
* **validation:** :bug: separate local declaration and assignment (SC2155) ([e9414bf](https://github.com/flowcore-io/usable-pr-validator/commit/e9414bf380113170b9b24ae66e9a62da6b676582))

## [1.5.2](https://github.com/flowcore-io/usable-pr-validator/compare/v1.5.1...v1.5.2) (2025-10-13)


### Bug Fixes

* test feature branch validation ([9dc3479](https://github.com/flowcore-io/usable-pr-validator/commit/9dc34793b879dd135d4c5238c9bfb1411a426a8b))
* test feature branch validation ([ed7af84](https://github.com/flowcore-io/usable-pr-validator/commit/ed7af84cba79da6c6316bdb60f07a15af6dd4da4))
* **validate.sh:** add a newline at the end of the script for better compatibility ([4246f34](https://github.com/flowcore-io/usable-pr-validator/commit/4246f34409cbf79f589d0e4753e42524487d74cc))
* **validate.sh:** enhance output handling and extraction for Gemini CLI ([2036ab5](https://github.com/flowcore-io/usable-pr-validator/commit/2036ab59c92a5931dd84aad6666416ab0b37b6a8))
* **validate.sh:** improve Gemini CLI output handling and error reporting ([3ef920d](https://github.com/flowcore-io/usable-pr-validator/commit/3ef920d98d7143f6f6db31078cb2c9578e8b5b4a))
* **validate.sh:** simplify Gemini CLI output handling and remove unnecessary complexity ([86871a6](https://github.com/flowcore-io/usable-pr-validator/commit/86871a629b0be807cb5fd1c0460fcbfa48d34661))

## [1.5.1](https://github.com/flowcore-io/usable-pr-validator/compare/v1.5.0...v1.5.1) (2025-10-12)


### Bug Fixes

* **mcp:** :adhesive_bandage: revert incorrect workspace-id header and add MCP debug output ([9e3a09c](https://github.com/flowcore-io/usable-pr-validator/commit/9e3a09ca1cefa766958a3e2a673d1c537cc10fb3))
* **mcp:** :bug: fix MCP workspace context and git pager issues ([67bcf4f](https://github.com/flowcore-io/usable-pr-validator/commit/67bcf4f6e85cd46fa1355b1fb79e26fd00a8df7a))

## [1.5.0](https://github.com/flowcore-io/usable-pr-validator/compare/v1.4.0...v1.5.0) (2025-10-12)


### Features

* **scripts:** add fix-tag-and-push script for managing 'latest' tag ([5bfe2f8](https://github.com/flowcore-io/usable-pr-validator/commit/5bfe2f8919167aa0b12fa3fe25c5d57b3e32fdcf))
* **tests:** add diagnostic script for git diff issues and enhance validation output ([51fe80b](https://github.com/flowcore-io/usable-pr-validator/commit/51fe80bf5bf6b76a5403ad994f5e5b12d1822f5b))


### Bug Fixes

* **scripts:** :wrench: fix ShellCheck SC2155 warnings and add tag fix script ([0a79912](https://github.com/flowcore-io/usable-pr-validator/commit/0a79912ed2c3a480358795a4a36347dc39a1b31c))

## [1.4.0](https://github.com/flowcore-io/usable-pr-validator/compare/v1.3.0...v1.4.0) (2025-10-10)


### Features

* **action:** :sparkles: add PR diff integration and enhanced validation ([8ad046b](https://github.com/flowcore-io/usable-pr-validator/commit/8ad046b10aec4b07b491f14fe37d53c8742f337a))

## [1.3.0](https://github.com/flowcore-io/usable-pr-validator/compare/v1.2.1...v1.3.0) (2025-10-08)


### Features

* **release:** :sparkles: add automatic latest tag update on release ([ef180d3](https://github.com/flowcore-io/usable-pr-validator/commit/ef180d374b3a6d84e1d0999fb1cf78524bd0e6c5))

## [1.2.1](https://github.com/flowcore-io/usable-pr-validator/compare/v1.2.0...v1.2.1) (2025-10-08)


### Bug Fixes

* **workflow:** update release-please action reference from google-github-actions to googleapis for consistency ([80df12c](https://github.com/flowcore-io/usable-pr-validator/commit/80df12c6f5aecbdf72746a4a43ba0fb502540ec0))

## [1.2.0](https://github.com/flowcore-io/usable-pr-validator/compare/v1.1.0...v1.2.0) (2025-10-08)


### Features

* **action:** :sparkles: enhance action inputs for dynamic prompt fetching and validation ([21cf10c](https://github.com/flowcore-io/usable-pr-validator/commit/21cf10c07350937b54a76f42cd47d0456b8db867))
* **comment-revalidation:** add support for comment-triggered revalidation and override handling in workflows and scripts ([7860dee](https://github.com/flowcore-io/usable-pr-validator/commit/7860dee10e4792be60a0fbee6d9af2602781d5dc))
* **workflow:** add logic to determine validation base reference for release-please branches ([ebfb323](https://github.com/flowcore-io/usable-pr-validator/commit/ebfb3233738d72f98513b23bc719e7e682c012fb))


### Bug Fixes

* **action:** improve base reference handling in Git fetch logic and update diff commands for better compatibility with branches and tags ([51f5721](https://github.com/flowcore-io/usable-pr-validator/commit/51f57210a329b7632f0f5eddb1c92ef209113ed8))
* **fetch-prompt:** streamline variable declarations and improve readability in fetch functions ([4a1f10c](https://github.com/flowcore-io/usable-pr-validator/commit/4a1f10ce4747976405c76e0e5ae4cc6f67d8712a))
* **scripts:** update shebang to use env for portability and improve error message clarity in fetch-prompt script ([b290c29](https://github.com/flowcore-io/usable-pr-validator/commit/b290c29f78b92ff7a1036199662d55edb41e98b4))
* **validate:** enhance Gemini CLI execution logging and output handling in validation script ([1251ea9](https://github.com/flowcore-io/usable-pr-validator/commit/1251ea9c0e5ad7e5fe68778c109293b820a89d19))
* **workflow:** replace console.log with core.info for improved logging in comment revalidation workflow; add warning for empty MCP system prompt content in fetch-prompt script; enhance logging in validate script for real-time output display ([fc36d88](https://github.com/flowcore-io/usable-pr-validator/commit/fc36d88caa7c8100e1e20cb8cab1e881cf38d27a))

## [1.1.0](https://github.com/flowcore-io/usable-pr-validator/compare/v1.0.0...v1.1.0) (2025-10-06)


### Features

* **action:** :sparkles: add base-ref and head-ref inputs for diff comparison ([ef77323](https://github.com/flowcore-io/usable-pr-validator/commit/ef7732354f5afffb01ef64c43e42dc2860552113))


### Bug Fixes

* **readme:** :memo: add a new line for better readability ([11a5399](https://github.com/flowcore-io/usable-pr-validator/commit/11a5399d4e66822284237bc4066c9b1505f9a6af))
* **readme:** :memo: update Usable PR Validator to use latest version ([4359c42](https://github.com/flowcore-io/usable-pr-validator/commit/4359c42d2fabae977ffb3dae0da39e14a56cdea2))

## 1.0.0 (2025-10-06)


### Features

* **action:** :sparkles: add support for custom artifact naming and comment title ([4e1ffe8](https://github.com/flowcore-io/usable-pr-validator/commit/4e1ffe8c78aa82349790092bb50171c9ab337f92))
* initial implementation of AI-Powered PR Validator ([c99d1ed](https://github.com/flowcore-io/usable-pr-validator/commit/c99d1eddf4cdfaf5612f4363772ef70510e59003))
* **workflow:** :sparkles: enhance integration tests with detailed validation prompts ([4c41292](https://github.com/flowcore-io/usable-pr-validator/commit/4c412927f672c081508f8221c2dce7cd28e158f5))


### Bug Fixes

* **ci:** :bug: add debug information for prompt file validation ([6ab421b](https://github.com/flowcore-io/usable-pr-validator/commit/6ab421b0a7f4d61960f5d24fedcd26f992f4f5d2))
* **ci:** :bug: add debug steps for action and documentation test results ([06bb48c](https://github.com/flowcore-io/usable-pr-validator/commit/06bb48c21155ee04e146d5ef326a5094d7d2df32))
* **ci:** :bug: enhance secret detection regex in workflow ([91f9c92](https://github.com/flowcore-io/usable-pr-validator/commit/91f9c923c19409ba18e791765f0d55e2bee65727))
* **ci:** :bug: enhance validation report extraction with error handling ([7daafe0](https://github.com/flowcore-io/usable-pr-validator/commit/7daafe003d278692cb4394bf55e96f4bb4bd268c))
* **ci:** :bug: enhance validation result parsing and GitHub output handling ([dd62319](https://github.com/flowcore-io/usable-pr-validator/commit/dd62319669371af57d0e47a2829da71362f47fc5))
* **ci:** :bug: improve GITHUB_OUTPUT handling in validation script ([fc855a1](https://github.com/flowcore-io/usable-pr-validator/commit/fc855a135900b5dc6db78d3de6adad10ee8fb45f))
* **ci:** :bug: improve prompt placeholder replacement and add validation checks ([9b33cae](https://github.com/flowcore-io/usable-pr-validator/commit/9b33cae1335f2c65b6295a3a749b030df0a8291e))
* **ci:** :bug: improve secret detection regex in workflow ([6b13c1e](https://github.com/flowcore-io/usable-pr-validator/commit/6b13c1e0c697b1477f659d907d986fd45551f945))
* **ci:** :bug: refine secret detection logic in workflow ([c0a293d](https://github.com/flowcore-io/usable-pr-validator/commit/c0a293db3426a9ee4e12a8dc6bffc523318dcddb))
* **ci:** :bug: update validation script to use heredoc for GitHub output handling ([cd6b0e0](https://github.com/flowcore-io/usable-pr-validator/commit/cd6b0e0f1fc5daf1926238b96d2f36317c9513ab))
* **ci:** exclude echo statements from security check ([5155c60](https://github.com/flowcore-io/usable-pr-validator/commit/5155c6047c097839302a241b1abe0446371ced56))
* **ci:** exclude grep command from security check ([e660a25](https://github.com/flowcore-io/usable-pr-validator/commit/e660a2597e4b4002c10983e8e8487d6b5df53a57))
* **ci:** fix YAML syntax error and security check pattern ([263c43c](https://github.com/flowcore-io/usable-pr-validator/commit/263c43cef55e34e12dbf44c9f1bb8779222b406c))
* **release:** :sparkles: add GitHub token to release-please configuration ([08d7962](https://github.com/flowcore-io/usable-pr-validator/commit/08d79621078ec560b48c7358f87029af19483833))
* **release:** :sparkles: add release-please configuration and manifest files ([cd8be5a](https://github.com/flowcore-io/usable-pr-validator/commit/cd8be5a69df9b5a8519f549dc2ddf444f4c6b683))
* **yaml:** replace template literal with string concatenation ([cb17945](https://github.com/flowcore-io/usable-pr-validator/commit/cb1794568a7436d480bd9fcb45bd32652e6271f8))

## [Unreleased]

### Added
- Initial implementation of Usable PR Validator
- Google Gemini integration via Vertex AI
- Composite GitHub Action with full configuration
- Prompt placeholder replacement system
- Report extraction with multiple fallback strategies
- PR comment posting with update/new/none modes
- Artifact uploading for validation reports
- Retry logic with exponential backoff
- MCP server integration support
- Example prompt templates (basic and MCP)
- Comprehensive documentation

### Security
- Secure secret handling with automatic cleanup
- Base64 decoding of service account keys
- Restrictive file permissions (600) on sensitive files
- No secret logging or exposure

## [1.0.0] - 2025-01-XX

### Added
- First stable release
- Complete feature set as per PRD v1.0
- GitHub Marketplace submission

---

**Legend**:
- `Added` for new features
- `Changed` for changes in existing functionality
- `Deprecated` for soon-to-be removed features
- `Removed` for now removed features
- `Fixed` for any bug fixes
- `Security` for vulnerability fixes
