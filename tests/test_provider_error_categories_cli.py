import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts/summarize-provider-error.py"
CANARY = "PRIVATE_PROMPT_TOKEN_BODY_CANARY"


class ProviderCategoryCliTests(unittest.TestCase):
    def run_cli(self, stdout, stderr="", mutate=None):
        with tempfile.TemporaryDirectory() as directory:
            out, err = Path(directory) / "out", Path(directory) / "err"
            out.write_text(stdout)
            err.write_text(stderr)
            if mutate:
                mutate(out)
            result = subprocess.run([sys.executable, str(SCRIPT), "--provider", "opencode",
                                     "--stdout-file", str(out), "--stderr-file", str(err)],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stderr, "")
            self.assertNotIn(CANARY, result.stdout + result.stderr)
            return json.loads(result.stdout)

    def test_unknown_error_messages_have_finite_categories_without_content(self):
        cases = {
            "context_limit": "maximum context length exceeded",
            "auth": "invalid API key",
            "quota": "insufficient credits",
            "rate_limit": "rate_limit_exceeded",
            "model_unavailable": "No endpoints found for model",
            "unsupported_parameter": "unsupported parameter temperature",
            "unsupported_api": "UnsupportedApiError: Unsupported API for model",
            "invalid_schema": "invalid schema for function",
            "local_transport": "TypeError: fetch failed ECONNREFUSED",
            "local_io": "ENOENT: no such file",
            "response_validation": "AI_TypeValidationError",
            "unknown": "opaque failure",
        }
        for category, message in cases.items():
            with self.subTest(category=category):
                event = {"type": "error", "error": {"name": "UnknownError", "data": {
                    "message": message + " " + CANARY, "responseHeaders": {"secret": CANARY}}}}
                value = self.run_cli(json.dumps(event), CANARY)
                self.assertEqual(value["failure_categories"], [category])
                self.assertEqual(value["error_names"], ["UnknownError"])
                self.assertEqual(value["status_codes"], [])
                self.assertEqual(value["error_codes"], [])
                self.assertIsNone(value["retryable"])

    def test_nested_response_body_is_classified_without_exporting_nested_fields(self):
        event = {"type": "error", "error": {"name": "UnknownError", "data": {
            "responseBody": json.dumps({"error": {"message": "context_length_exceeded " + CANARY,
                                                  "code": CANARY, "statusCode": 401}})}}}
        value = self.run_cli(json.dumps(event))
        self.assertEqual(value["failure_categories"], ["context_limit"])
        self.assertEqual(value["error_codes"], [])
        self.assertEqual(value["status_codes"], [])

    def test_prompt_tool_events_stderr_and_arbitrary_fields_are_not_classified(self):
        events = [{"type": "text", "part": {"text": "context_length_exceeded " + CANARY}},
                  {"type": "tool_use", "error": {"message": "invalid API key " + CANARY}},
                  {"type": "error", "error": {"name": CANARY, "data": {"secret": "invalid schema " + CANARY}}}]
        value = self.run_cli("\n".join(json.dumps(x) for x in events), "ENOENT " + CANARY)
        self.assertEqual(value["failure_categories"], ["unknown"])
        self.assertEqual(value["error_names"], ["unrecognized"])
        self.assertEqual(value["structured_error_events"], 1)

    def test_nested_arbitrary_fields_are_ignored(self):
        event = {"type": "error", "error": {"name": "UnknownError", "data": {
            "responseBody": json.dumps({"secret": "invalid API key " + CANARY})}}}
        value = self.run_cli(json.dumps(event))
        self.assertEqual(value["failure_categories"], ["unknown"])

    def test_malformed_and_deep_json_are_fixed_metadata_only(self):
        value = self.run_cli(CANARY + "\n" + "[" * 2000 + "]" * 2000)
        self.assertEqual(value["failure_categories"], [])
        # Decoder depth limits vary; a valid non-error array may be ignored.
        self.assertIn(value["malformed_output_lines"], (1, 2))

    def test_huge_numeric_json_never_emits_tracebacks(self):
        value = self.run_cli('{"type":"error","error":{"data":{"code":' + "9" * 5000 + '}}}')
        if hasattr(sys, "get_int_max_str_digits") and sys.get_int_max_str_digits():
            self.assertEqual(value["malformed_output_lines"], 1)
            self.assertEqual(value["failure_categories"], [])
        else:
            self.assertEqual(value["failure_categories"], ["unknown"])

    def test_missing_oversized_and_symlink_inputs_are_unavailable(self):
        for operation in ["missing", "oversized", "symlink"]:
            def mutate(path):
                if operation == "missing":
                    path.unlink()
                elif operation == "oversized":
                    with path.open("wb") as stream:
                        stream.truncate(16 * 1024 * 1024 + 1)
                else:
                    target = path.with_name("private")
                    target.write_text(CANARY)
                    path.unlink()
                    path.symlink_to(target)
            with self.subTest(operation=operation):
                value = self.run_cli("", mutate=mutate)
                self.assertEqual(value["failure_categories"], ["input_unavailable"])


if __name__ == "__main__":
    unittest.main()
