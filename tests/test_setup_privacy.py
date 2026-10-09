"""Black-box confidentiality checks for prompt and MCP setup helpers."""

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).parents[1]


class SetupPrivacyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.private = self.directory / "private"
        self.private.mkdir()
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        curl = self.bin / "curl"
        curl.write_text(
            "#!/bin/sh\n"
            "case \"$*\" in\n"
            "  *mcp-system-prompt*) printf '%s\\n%s' \"$MOCK_MCP_BODY\" \"$MOCK_MCP_CODE\" ;;\n"
            "  *) printf '%s\\n%s' \"$MOCK_FRAGMENT_BODY\" \"$MOCK_FRAGMENT_CODE\" ;;\n"
            "esac\n"
        )
        curl.chmod(0o755)

    def script(self, name):
        # Isolate the helpers' fixed temporary paths so these tests can run in
        # parallel with the action or another local test invocation.
        source = (ROOT / "scripts" / name).read_text()
        copied = self.directory / name
        copied.write_text(source.replace("/tmp/", str(self.private) + "/"))
        copied.chmod(0o755)
        return copied

    def run_script(self, name, **environment):
        variables = os.environ.copy()
        variables.update({
            "PATH": str(self.bin) + os.pathsep + variables.get("PATH", ""),
            "MCP_SECRET_NAME": "TEST_USABLE_TOKEN",
            "WORKSPACE_ID": "f3c9feef-b8e6-4a23-bda0-0d90cd5162d1",
            "USE_DYNAMIC_PROMPTS": "false",
            "MOCK_MCP_BODY": "{}",
            "MOCK_MCP_CODE": "200",
            "MOCK_FRAGMENT_BODY": "{}",
            "MOCK_FRAGMENT_CODE": "200",
            **environment,
        })
        return subprocess.run(
            ["bash", str(self.script(name))],
            cwd=self.directory,
            env=variables,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_private(self, filename):
        self.assertEqual(stat.S_IMODE((self.private / filename).stat().st_mode), 0o600)

    def test_short_system_and_static_prompt_are_not_previewed(self):
        action = self.directory / "action"
        action.mkdir()
        (action / "system-prompt.md").write_text("PRIVATE_SYSTEM_CANARY\n")
        custom = self.directory / "custom.md"
        custom.write_text("PRIVATE_STATIC_PROMPT_CANARY\n")
        result = self.run_script(
            "fetch-prompt.sh",
            ACTION_PATH=str(action),
            CUSTOM_PROMPT_FILE=str(custom),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for canary in ("PRIVATE_SYSTEM_CANARY", "PRIVATE_STATIC_PROMPT_CANARY"):
            self.assertNotIn(canary, result.stdout + result.stderr)
            self.assertIn(canary, (self.private / "dynamic-prompt.md").read_text())
        self.assert_private("user-prompt.md")
        self.assert_private("dynamic-prompt.md")

    def test_dynamic_usable_content_stays_private_with_no_system_file(self):
        action = self.directory / "missing-system"
        action.mkdir()
        mcp = "PRIVATE_MCP_PROMPT_CANARY"
        fragment = "PRIVATE_FRAGMENT_PROMPT_CANARY"
        result = self.run_script(
            "fetch-prompt.sh",
            ACTION_PATH=str(action),
            USE_DYNAMIC_PROMPTS="true",
            PROMPT_FRAGMENT_ID="a03af556-b85c-4073-8383-08ea7b2b3b8d",
            TEST_USABLE_TOKEN="synthetic-token",
            MOCK_MCP_BODY=json.dumps({"content": mcp}),
            MOCK_FRAGMENT_BODY=json.dumps({"success": True, "fragment": {"content": fragment}}),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for canary in (mcp, fragment):
            self.assertNotIn(canary, result.stdout + result.stderr)
            self.assertIn(canary, (self.private / "dynamic-prompt.md").read_text())
        for filename in ("mcp-system-prompt.md", "user-prompt.md", "dynamic-prompt.md"):
            self.assert_private(filename)

    def test_non_200_response_body_never_reaches_diagnostics(self):
        action = self.directory / "missing-system"
        action.mkdir()
        result = self.run_script(
            "fetch-prompt.sh",
            ACTION_PATH=str(action),
            USE_DYNAMIC_PROMPTS="true",
            PROMPT_FRAGMENT_ID="a03af556-b85c-4073-8383-08ea7b2b3b8d",
            TEST_USABLE_TOKEN="synthetic-token",
            MOCK_MCP_BODY=json.dumps({"content": "PRIVATE_MCP_CANARY"}),
            MOCK_FRAGMENT_BODY="PRIVATE_HTTP_RESPONSE_BODY_CANARY",
            MOCK_FRAGMENT_CODE="403",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to fetch fragment content", result.stderr)
        self.assertNotIn("PRIVATE_HTTP_RESPONSE_BODY_CANARY", result.stdout + result.stderr)
        self.assertNotIn("PRIVATE_MCP_CANARY", result.stdout + result.stderr)

    def test_config_preview_cannot_leak_quoted_multiline_credential(self):
        secret = 'synthetic"\nPRIVATE_CREDENTIAL_CANARY'
        for provider, filename in (("opencode", "opencode.json"), ("gemini", "gemini-settings.json")):
            with self.subTest(provider=provider):
                result = self.run_script(
                    "setup-mcp.sh",
                    PROVIDER=provider,
                    TEST_USABLE_TOKEN=secret,
                    MCP_URL="https://usable.dev/api/mcp?access=PRIVATE_URL_CANARY",
                    OPENCODE_PROVIDER="openrouter",
                    OPENCODE_MODEL="test/model",
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("PRIVATE_CREDENTIAL_CANARY", result.stdout + result.stderr)
                self.assertNotIn("PRIVATE_URL_CANARY", result.stdout + result.stderr)
                self.assertNotIn("Configuration preview", result.stdout + result.stderr)
                self.assert_private(filename)
                if provider == "opencode":
                    self.assertEqual(stat.S_IMODE((self.directory / "opencode.json").stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
