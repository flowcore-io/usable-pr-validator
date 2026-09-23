import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

ROOT = Path(__file__).parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ValidationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parser = load("report_parser", "parse-validation-report.py")
        cls.ledger = load("grounding_ledger", "check-grounding-ledger.py")
        cls.enforcer = load("grounding_enforcer", "enforce-grounding-report.py")
        cls.prefetch = load("grounding_prefetch", "prefetch-usable-fragments.py")
        cls.reader = load("grounding_reader", "read-usable-fragment.py")

    def test_exact_structured_pass_is_accepted(self):
        report = """# PR Validation Report

## Summary
Validated.

## Validation Outcome
- **Status**: PASS ✅
- **Critical Issues**: 0
- **Important Issues**: 1
- **Suggestions**: 0
"""
        result = self.parser.parse_report(report)
        self.assertEqual(result, {"status": "passed", "passed": True, "critical_issues": 0})

    def test_checkmark_transcript_without_report_is_rejected(self):
        with self.assertRaises(ValueError):
            self.parser.parse_report("✅ Tool completed successfully\nStatus maybe PASS")

    def test_ambiguous_or_inconsistent_verdict_is_rejected(self):
        cases = [
            "# PR Validation Report\n## Validation Outcome\n- **Status**: PASS ✅\n- **Status**: FAIL ❌\n- **Critical Issues**: 1\n",
            "# PR Validation Report\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 2\n",
            "# PR Validation Report\n## Validation Outcome\n- **Status**: FAIL ❌\n- **Critical Issues**: 0\n",
            "# PR Validation Report\n## Summary\nLooks good ✅\n",
        ]
        for report in cases:
            with self.subTest(report=report):
                with self.assertRaises(ValueError):
                    self.parser.parse_report(report)

    def test_ai_pass_cannot_override_missing_required_grounding(self):
        with tempfile.TemporaryDirectory() as directory:
            required = Path(directory) / "required.txt"
            ledger = Path(directory) / "ledger.jsonl"
            required.write_text("a03af556-b85c-4073-8383-08ea7b2b3b8d\n")
            ledger.write_text("")
            result = self.ledger.evaluate(required, ledger)
            self.assertEqual(result["status"], "incomplete")
            self.assertEqual(result["missing_required"], ["a03af556-b85c-4073-8383-08ea7b2b3b8d"])
            report = "# PR Validation Report\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 0\n"
            enforced = self.enforcer.enforce(report, "incomplete", 1, 1, 0)
            parsed = self.parser.parse_report(enforced)
            self.assertEqual(parsed, {"status": "failed", "passed": False, "critical_issues": 1})
            self.assertIn("Grounding Status", enforced)

    def test_failed_attempt_keeps_grounding_incomplete_even_after_other_success(self):
        with tempfile.TemporaryDirectory() as directory:
            required = Path(directory) / "required.txt"
            ledger = Path(directory) / "ledger.jsonl"
            required.write_text("a03af556-b85c-4073-8383-08ea7b2b3b8d\n")
            records = [
                {"fragment_id": "a03af556-b85c-4073-8383-08ea7b2b3b8d", "status": "success"},
                {"fragment_id": "11111111-1111-4111-8111-111111111111", "status": "failed", "error": "http_404"},
            ]
            ledger.write_text("".join(json.dumps(record) + "\n" for record in records))
            result = self.ledger.evaluate(required, ledger)
            self.assertEqual(result["status"], "incomplete")
            self.assertEqual(result["failed_attempts"], ["11111111-1111-4111-8111-111111111111"])

    def test_all_required_reads_complete_and_empty_set_is_not_certified(self):
        with tempfile.TemporaryDirectory() as directory:
            required = Path(directory) / "required.txt"
            ledger = Path(directory) / "ledger.jsonl"
            required.write_text("a03af556-b85c-4073-8383-08ea7b2b3b8d\n")
            ledger.write_text(json.dumps({
                "fragment_id": "a03af556-b85c-4073-8383-08ea7b2b3b8d",
                "status": "success",
            }) + "\n")
            self.assertEqual(self.ledger.evaluate(required, ledger)["status"], "complete")
            required.write_text("")
            ledger.write_text("")
            self.assertEqual(self.ledger.evaluate(required, ledger)["status"], "not-required")

    def test_prefetch_success_followed_by_malformed_extra_read_cannot_pass(self):
        fragment_id = "a03af556-b85c-4073-8383-08ea7b2b3b8d"
        workspace_id = "f3c9feef-b8e6-4a23-bda0-0d90cd5162d1"
        with tempfile.TemporaryDirectory() as directory:
            required = Path(directory) / "required.txt"
            ledger = Path(directory) / "ledger.jsonl"
            output = Path(directory) / "grounding.md"
            alternate = Path(directory) / "alternate.jsonl"
            fragment = {
                "id": fragment_id,
                "title": "Policy",
                "workspaceId": workspace_id,
                "updatedAt": None,
                "content": "complete content",
            }
            with mock.patch.object(self.prefetch.reader, "read_fragment", return_value=fragment), \
                 redirect_stdout(io.StringIO()):
                result = self.prefetch.main([
                    "--ids", fragment_id,
                    "--workspace-id", workspace_id,
                    "--required-file", str(required),
                    "--ledger", str(ledger),
                    "--output", str(output),
                ])
            self.assertEqual(result, 0)
            self.assertEqual(self.ledger.evaluate(required, ledger)["status"], "complete")

            environment = {
                "WORKSPACE_ID": workspace_id,
                "USABLE_GROUNDING_LEDGER": str(ledger),
            }
            with mock.patch.dict(os.environ, environment, clear=False), redirect_stderr(io.StringIO()):
                malformed = self.reader.main([fragment_id, "--ledger", str(alternate)])
            self.assertEqual(malformed, 2)
            self.assertFalse(alternate.exists())
            evaluated = self.ledger.evaluate(required, ledger)
            self.assertEqual(evaluated["status"], "incomplete")
            self.assertEqual(evaluated["failed_attempts"], ["invalid-input"])

    def test_provider_transcripts_are_private_and_only_report_is_uploaded(self):
        validation = (ROOT / "scripts" / "validate.sh").read_text()
        action = (ROOT / "action.yml").read_text()
        self.assertNotIn("| tee /tmp/validation-full-output.md", validation)
        self.assertIn('gemini -y -m "$GEMINI_MODEL" < "$prompt_file" > /tmp/validation-full-output.md 2>&1', validation)
        self.assertIn('opencode run -m "$full_model" < "$prompt_file" > /tmp/validation-full-output.md 2>&1', validation)
        self.assertGreaterEqual(validation.count("chmod 600 /tmp/validation-full-output.md"), 2)
        self.assertNotIn("Upload Full Output", action)
        self.assertNotIn("artifact_name }}-full", action)
        self.assertNotIn("path: /tmp/validation-full-output.md", action)
        self.assertIn("path: /tmp/validation-report.md", action)


if __name__ == "__main__":
    unittest.main()
