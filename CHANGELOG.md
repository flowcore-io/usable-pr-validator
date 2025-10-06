# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial implementation of AI-Powered PR Validator
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
