"""Regression tests for optional workspace prompt retrieval."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class FetchPromptTests(unittest.TestCase):
    def run_fetch(self, *, status="200", body='{"content":"MCP CONTEXT"}', curl_exit="0", dynamic=False):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            bin_dir = temporary / "bin"
            bin_dir.mkdir()
            fake_curl = bin_dir / "curl"
            fake_curl.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n%s' \"$MOCK_CURL_BODY\" \"$MOCK_CURL_STATUS\"\n"
                "exit \"$MOCK_CURL_EXIT\"\n"
            )
            fake_curl.chmod(0o755)
            (temporary / "system-prompt.md").write_text("SYSTEM\n")
            (temporary / "source-user-prompt.md").write_text("USER\n")
            environment = {
                **os.environ,
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "ACTION_PATH": str(temporary),
                "PROMPT_OUTPUT_DIR": str(temporary),
                "MCP_SECRET_NAME": "MOCK_API_TOKEN",
                "MOCK_API_TOKEN": "test-token",
                "WORKSPACE_ID": "test-workspace",
                "USE_DYNAMIC_PROMPTS": "true" if dynamic else "false",
                "PROMPT_FRAGMENT_ID": "test-fragment" if dynamic else "",
                "CUSTOM_PROMPT_FILE": str(temporary / "source-user-prompt.md"),
                "MOCK_CURL_BODY": body,
                "MOCK_CURL_STATUS": status,
                "MOCK_CURL_EXIT": curl_exit,
            }
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/fetch-prompt.sh")],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            prompt_file = temporary / "dynamic-prompt.md"
            prompt = prompt_file.read_text() if prompt_file.exists() else None
            return result, prompt

    def test_optional_http_failure_keeps_required_prompts(self):
        result, prompt = self.run_fetch(status="503", body="unavailable")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SYSTEM", prompt)
        self.assertIn("USER", prompt)
        self.assertNotIn("unavailable", prompt)
        self.assertIn("continuing without it", result.stderr)

    def test_optional_network_failure_keeps_required_prompts(self):
        result, prompt = self.run_fetch(curl_exit="7")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SYSTEM", prompt)
        self.assertIn("USER", prompt)
        self.assertNotIn("MCP CONTEXT", prompt)

    def test_successful_fetch_adds_only_prompt_content(self):
        result, prompt = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("MCP CONTEXT", prompt)
        self.assertNotIn("Fetching MCP", prompt)

    def test_required_dynamic_user_prompt_still_fails(self):
        result, prompt = self.run_fetch(status="503", body="unavailable", dynamic=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(prompt)


if __name__ == "__main__":
    unittest.main()
