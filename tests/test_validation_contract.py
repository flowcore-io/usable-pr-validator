import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
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
        cls.extractor = load("provider_report_extractor", "extract-provider-report.py")

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
            attempt_id = "22222222-2222-4222-8222-222222222222"
            ledger.write_text("".join(json.dumps(record) + "\n" for record in [
                {
                    "fragment_id": "11111111-1111-4111-8111-111111111111",
                    "attempt_id": attempt_id,
                    "status": "pending",
                },
                {
                    "fragment_id": "11111111-1111-4111-8111-111111111111",
                    "attempt_id": attempt_id,
                    "status": "success",
                },
            ]))
            self.assertEqual(self.ledger.evaluate(required, ledger)["status"], "not-required")

    def test_unfinished_attempt_keeps_grounding_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            required = Path(directory) / "required.txt"
            ledger = Path(directory) / "ledger.jsonl"
            required.write_text("a03af556-b85c-4073-8383-08ea7b2b3b8d\n")
            records = [
                {"fragment_id": "a03af556-b85c-4073-8383-08ea7b2b3b8d", "status": "success"},
                {
                    "fragment_id": "11111111-1111-4111-8111-111111111111",
                    "attempt_id": "22222222-2222-4222-8222-222222222222",
                    "status": "pending",
                },
            ]
            ledger.write_text("".join(json.dumps(record) + "\n" for record in records))
            result = self.ledger.evaluate(required, ledger)
            self.assertEqual(result["status"], "incomplete")
            self.assertEqual(result["failed_attempts"], ["11111111-1111-4111-8111-111111111111"])

    def test_structured_provider_output_uses_only_final_assistant_answer(self):
        private_sentinel = "PRIVATE_TOOL_SENTINEL"
        tool_report = "# PR Validation Report\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 0"
        final_answer = "I could not complete the review because required evidence was unavailable."
        message_id = "msg-final"
        opencode_events = "\n".join([
            json.dumps({
                "type": "tool_use",
                "part": {"type": "tool", "messageID": "msg-earlier", "state": {"status": "completed", "output": tool_report + "\n" + private_sentinel}},
            }),
            json.dumps({"type": "step_start", "part": {"type": "step-start", "messageID": message_id}}),
            json.dumps({"type": "text", "part": {"type": "text", "messageID": message_id, "text": final_answer, "time": {"end": 1}}}),
            json.dumps({"type": "step_finish", "part": {"type": "step-finish", "messageID": message_id, "reason": "stop"}}),
        ]) + "\n"
        extracted = self.extractor.extract("opencode", opencode_events)
        self.assertEqual(extracted, final_answer)
        self.assertNotIn(private_sentinel, extracted)
        with self.assertRaises(ValueError):
            self.parser.parse_report(extracted)

        gemini_output = json.dumps({"response": final_answer, "stats": {"models": {}}})
        self.assertEqual(self.extractor.extract("gemini", gemini_output), final_answer)

    def test_rejected_candidate_is_never_the_publishable_report(self):
        validation = (ROOT / "scripts" / "validate.sh").read_text()
        self.assertIn('mktemp /tmp/validation-report.candidate.XXXXXX', validation)
        self.assertNotIn('sed -n \'/^# PR Validation Report$/,$p\' "$full_output" > "$report_file"', validation)
        self.assertIn('mv -f "$candidate_file" /tmp/validation-report.md', validation)
        self.assertIn('publish_safe_error_report', validation)

    def test_orchestration_rejects_tool_pass_and_publishes_only_safe_error(self):
        private_sentinel = "PRIVATE_TOOL_SENTINEL"
        tool_report = "# PR Validation Report\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 0"
        final_answer = "I could not complete the review."
        message_id = "msg-final"
        events = "\n".join([
            json.dumps({
                "type": "tool_use",
                "part": {"type": "tool", "messageID": "msg-earlier", "state": {"status": "completed", "output": tool_report + "\n" + private_sentinel}},
            }),
            json.dumps({"type": "step_start", "part": {"type": "step-start", "messageID": message_id}}),
            json.dumps({"type": "text", "part": {"type": "text", "messageID": message_id, "text": final_answer, "time": {"end": 1}}}),
            json.dumps({"type": "step_finish", "part": {"type": "step-finish", "messageID": message_id, "reason": "stop"}}),
        ]) + "\n"
        report_path = Path("/tmp/validation-report.md")
        report_path.unlink(missing_ok=True)
        try:
            with tempfile.TemporaryDirectory() as directory:
                provider_output = Path(directory) / "opencode.jsonl"
                candidate = Path(directory) / "candidate.md"
                provider_output.write_text(events)
                script = f'''set -euo pipefail
export ACTION_PATH={ROOT!s}
export VALIDATE_SH_LIBRARY_ONLY=true
source {ROOT / "scripts" / "validate.sh"}
if extract_report {provider_output!s} opencode {candidate!s}; then
  exit 99
fi
rm -f {candidate!s}
publish_safe_error_report "The final assistant response was invalid."
'''
                completed = subprocess.run(["bash", "-c", script], text=True, capture_output=True, check=False)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                published = report_path.read_text()
                self.assertNotIn(private_sentinel, published)
                self.assertNotIn(tool_report, published)
                self.assertIn("Validation infrastructure failure", published)
                self.assertEqual(
                    self.parser.parse_report(published),
                    {"status": "failed", "passed": False, "critical_issues": 1},
                )
        finally:
            report_path.unlink(missing_ok=True)

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
        self.assertIn('gemini -y -m "$GEMINI_MODEL" --output-format json < "$prompt_file" > /tmp/validation-full-output.md 2> /tmp/validation-provider-stderr.log', validation)
        self.assertIn('opencode run --format json -m "$full_model" < "$prompt_file" > /tmp/validation-full-output.md 2> /tmp/validation-provider-stderr.log', validation)
        self.assertGreaterEqual(validation.count("chmod 600 /tmp/validation-full-output.md"), 2)
        self.assertNotIn("Upload Full Output", action)
        self.assertNotIn("artifact_name }}-full", action)
        self.assertNotIn("path: /tmp/validation-full-output.md", action)
        self.assertIn("path: /tmp/validation-report.md", action)

    def test_opencode_assembles_only_multipart_text_from_terminal_step(self):
        earlier_pass = "# PR Validation Report\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 0"
        final_message = "msg-final"
        events = "\n".join([
            json.dumps({"type": "step_start", "part": {"type": "step-start", "messageID": "msg-earlier"}}),
            json.dumps({"type": "text", "part": {"type": "text", "messageID": "msg-earlier", "text": earlier_pass, "time": {"end": 1}}}),
            json.dumps({"type": "step_finish", "part": {"type": "step-finish", "messageID": "msg-earlier", "reason": "tool-calls"}}),
            json.dumps({"type": "tool_use", "part": {"type": "tool", "messageID": final_message, "state": {"status": "completed", "output": earlier_pass}}}),
            json.dumps({"type": "step_start", "part": {"type": "step-start", "messageID": final_message}}),
            json.dumps({"type": "text", "part": {"type": "text", "messageID": final_message, "text": "# PR Validation Report\n\n## Summary\nValidated.", "time": {"end": 2}}}),
            json.dumps({"type": "text", "part": {"type": "text", "messageID": final_message, "text": "## Validation Outcome\n- **Status**: FAIL ❌\n- **Critical Issues**: 1", "time": {"end": 3}}}),
            json.dumps({"type": "step_finish", "part": {"type": "step-finish", "messageID": final_message, "reason": "stop"}}),
        ]) + "\n"

        extracted = self.extractor.extract("opencode", events)
        self.assertNotIn(earlier_pass, extracted)
        self.assertEqual(self.parser.parse_report(extracted)["status"], "failed")

    def test_opencode_rejects_incomplete_error_or_tool_terminal_events(self):
        message_id = "msg-final"
        cases = [
            [
                {"type": "step_start", "part": {"type": "step-start", "messageID": message_id}},
                {"type": "text", "part": {"type": "text", "messageID": message_id, "text": "# PR Validation Report", "time": {"end": 1}}},
            ],
            [
                {"type": "step_start", "part": {"type": "step-start", "messageID": message_id}},
                {"type": "error", "error": {"name": "ProviderError", "data": {"message": "private"}}},
            ],
            [
                {"type": "step_start", "part": {"type": "step-start", "messageID": message_id}},
                {"type": "tool_use", "part": {"type": "tool", "messageID": message_id, "state": {"status": "completed", "output": "private"}}},
            ],
        ]
        for events in cases:
            with self.subTest(terminal=events[-1]["type"]):
                output = "\n".join(json.dumps(event) for event in events) + "\n"
                with self.assertRaises(ValueError):
                    self.extractor.extract("opencode", output)

    def test_harmless_report_wrapping_is_normalized_but_multiple_reports_fail(self):
        report = "# PR Validation Report\n\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 0"
        wrapped = "Here is the requested PR validation report:\n\n```markdown\n" + report + "\n```\n"
        self.assertEqual(self.parser.normalize_report(wrapped), report)
        self.assertTrue(self.parser.parse_report(wrapped)["passed"])
        with self.assertRaises(ValueError):
            self.parser.parse_report("I reviewed the changes.\n\n" + report)
        with self.assertRaises(ValueError):
            self.parser.parse_report(report + "\n\n" + report)

    def test_extractor_diagnostics_are_metadata_only(self):
        private_sentinel = "PRIVATE_TRANSCRIPT_SENTINEL"
        message_id = "msg-final"
        events = "\n".join([
            json.dumps({"type": "tool_use", "part": {"type": "tool", "messageID": message_id, "state": {"status": "completed", "output": private_sentinel}}}),
            json.dumps({"type": "step_start", "part": {"type": "step-start", "messageID": message_id}}),
            json.dumps({"type": "text", "part": {"type": "text", "messageID": message_id, "text": "# PR Validation Report", "time": {"end": 1}}}),
            json.dumps({"type": "step_finish", "part": {"type": "step-finish", "messageID": message_id, "reason": "stop"}}),
        ]) + "\n"
        extracted, diagnostics = self.extractor.extract_with_diagnostics("opencode", events)
        rendered = json.dumps(diagnostics, sort_keys=True)
        self.assertEqual(extracted, "# PR Validation Report")
        self.assertNotIn(private_sentinel, rendered)
        self.assertEqual(diagnostics["selected_text_parts"], 1)
        self.assertEqual(diagnostics["terminal_event"], "step_finish")

        with tempfile.TemporaryDirectory() as directory:
            provider_output = Path(directory) / "opencode.jsonl"
            provider_output.write_text("\n".join([
                json.dumps({"type": "step_start", "part": {"type": "step-start", "messageID": message_id}}),
                json.dumps({"type": "error", "error": {"name": "ProviderError", "data": {"message": private_sentinel}}}),
            ]) + "\n")
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                result = self.extractor.main(["--provider", "opencode", str(provider_output)])
            self.assertEqual(result, 1)
            self.assertNotIn(private_sentinel, stderr.getvalue())

    def test_orchestration_normalizes_harmless_final_response_wrapping(self):
        report = "# PR Validation Report\n\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 0"
        wrapped = "Here is the requested PR validation report:\n\n```markdown\n" + report + "\n```"
        message_id = "msg-final"
        events = "\n".join([
            json.dumps({"type": "step_start", "part": {"type": "step-start", "messageID": message_id}}),
            json.dumps({"type": "text", "part": {"type": "text", "messageID": message_id, "text": wrapped, "time": {"end": 1}}}),
            json.dumps({"type": "step_finish", "part": {"type": "step-finish", "messageID": message_id, "reason": "stop"}}),
        ]) + "\n"
        with tempfile.TemporaryDirectory() as directory:
            provider_output = Path(directory) / "opencode.jsonl"
            candidate = Path(directory) / "candidate.md"
            provider_output.write_text(events)
            script = f'''set -euo pipefail
export ACTION_PATH={ROOT!s}
export VALIDATE_SH_LIBRARY_ONLY=true
source {ROOT / "scripts" / "validate.sh"}
extract_report {provider_output!s} opencode {candidate!s}
'''
            completed = subprocess.run(["bash", "-c", script], text=True, capture_output=True, check=False)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(candidate.read_text().strip(), report)


if __name__ == "__main__":
    unittest.main()
