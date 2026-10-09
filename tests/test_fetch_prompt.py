"""Regression tests for optional workspace prompt retrieval."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class FetchPromptTests(unittest.TestCase):
    def run_fetch(
        self,
        *,
        mcp_status="200",
        mcp_body='{"success":true,"systemPrompt":"MCP CONTEXT","metadata":"NOT PROMPT"}',
        mcp_exit="0",
        fragment_status="200",
        fragment_body='{"success":true,"fragment":{"content":"REAL USER PROMPT BODY"},"metadata":"NOT PROMPT"}',
        fragment_exit="0",
        dynamic=False,
    ):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            bin_dir = temporary / "bin"
            bin_dir.mkdir()
            fake_curl = bin_dir / "curl"
            fake_curl.write_text(
                "#!/usr/bin/env bash\n"
                "case \"$*\" in\n"
                "  */mcp-system-prompt*)\n"
                "    body=$MOCK_MCP_BODY; status=$MOCK_MCP_STATUS; rc=$MOCK_MCP_EXIT ;;\n"
                "  *https://usable.dev/api/memory-fragments/*)\n"
                "    body=$MOCK_FRAGMENT_BODY; status=$MOCK_FRAGMENT_STATUS; rc=$MOCK_FRAGMENT_EXIT ;;\n"
                "  *) exit 99 ;;\n"
                "esac\n"
                "if [ \"$rc\" -ne 0 ]; then exit \"$rc\"; fi\n"
                "printf '%s\\n%s' \"$body\" \"$status\"\n"
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
                "MOCK_MCP_BODY": mcp_body,
                "MOCK_MCP_STATUS": mcp_status,
                "MOCK_MCP_EXIT": mcp_exit,
                "MOCK_FRAGMENT_BODY": fragment_body,
                "MOCK_FRAGMENT_STATUS": fragment_status,
                "MOCK_FRAGMENT_EXIT": fragment_exit,
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
            user_prompt_file = temporary / "user-prompt.md"
            user_prompt = user_prompt_file.read_text() if user_prompt_file.exists() else None
            return result, prompt, user_prompt

    def test_optional_http_failure_keeps_required_prompts(self):
        result, prompt, _ = self.run_fetch(mcp_status="503", mcp_body="unavailable")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNotNone(prompt)
        self.assertIn("SYSTEM", prompt)
        self.assertIn("USER", prompt)
        self.assertNotIn("unavailable", prompt)
        self.assertIn("continuing without it", result.stderr)

    def test_optional_network_failure_keeps_required_prompts(self):
        result, prompt, _ = self.run_fetch(mcp_exit="7")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNotNone(prompt)
        self.assertIn("SYSTEM", prompt)
        self.assertIn("USER", prompt)
        self.assertNotIn("MCP CONTEXT", prompt)

    def test_successful_fetch_adds_only_prompt_content(self):
        result, prompt, _ = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNotNone(prompt)
        self.assertIn("MCP CONTEXT", prompt)
        self.assertNotIn("Fetching MCP", prompt)

    def test_required_dynamic_user_prompt_still_fails(self):
        result, prompt, _ = self.run_fetch(fragment_status="503", fragment_body="unavailable", dynamic=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(prompt)
        self.assertIn("::error::Failed to fetch fragment content (HTTP 503)", result.stderr)

    def test_dynamic_prompt_contains_only_fragment_body(self):
        result, prompt, user_prompt = self.run_fetch(dynamic=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(user_prompt, "REAL USER PROMPT BODY\n")
        self.assertIsNotNone(prompt)
        self.assertIn("REAL USER PROMPT BODY", prompt)
        self.assertNotIn("Fetching fragment content", prompt)

    def test_optional_failure_does_not_block_required_dynamic_prompt(self):
        result, prompt, user_prompt = self.run_fetch(mcp_status="503", mcp_body="unavailable", dynamic=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(user_prompt, "REAL USER PROMPT BODY\n")
        self.assertIsNotNone(prompt)
        self.assertIn("SYSTEM", prompt)
        self.assertIn("REAL USER PROMPT BODY", prompt)
        self.assertNotIn("unavailable", prompt)
        self.assertIn("continuing without it", result.stderr)

    def test_workspace_envelope_does_not_become_prompt_text(self):
        result, prompt, _ = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("MCP CONTEXT", prompt)
        self.assertNotIn("systemPrompt", prompt)
        self.assertNotIn("NOT PROMPT", prompt)

    def test_legacy_workspace_text_formats_remain_supported(self):
        for body in ('{"content":"LEGACY"}', '{"prompt":"LEGACY"}', 'LEGACY'):
            with self.subTest(body=body):
                result, prompt, _ = self.run_fetch(mcp_body=body)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("LEGACY", prompt)

    def test_invalid_optional_envelopes_do_not_become_prompt_text(self):
        for body in ('{"success":true,"metadata":"NOT PROMPT"}', '{"systemPrompt":42}', '{"systemPrompt":""}', '{"systemPrompt":', 'false', 'null', ''):
            with self.subTest(body=body):
                result, prompt, user_prompt = self.run_fetch(mcp_body=body, dynamic=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(user_prompt, "REAL USER PROMPT BODY\n")
                self.assertNotIn("NOT PROMPT", prompt)
                self.assertNotIn("systemPrompt", prompt)
                self.assertIn("continuing without it", result.stderr)

    def test_invalid_required_fragment_envelopes_fail_closed(self):
        for body in ('{"content":"LEGACY"}', '{"success":false,"fragment":{"content":"BAD"}}', '{"success":true,"fragment":{"content":42}}', '{"success":true,"fragment":{"content":""}}', 'not JSON'):
            with self.subTest(body=body):
                result, prompt, user_prompt = self.run_fetch(fragment_body=body, dynamic=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(prompt)
                self.assertIsNone(user_prompt)

    def test_required_fragment_network_failure_fails_closed(self):
        result, prompt, _ = self.run_fetch(fragment_exit="7", dynamic=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(prompt)
        self.assertIn("::error::Failed to fetch fragment content", result.stderr)

    def test_fragment_failure_does_not_log_response_content(self):
        result, _, _ = self.run_fetch(fragment_status="401", fragment_body="PRIVATE RESPONSE", dynamic=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PRIVATE RESPONSE", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
