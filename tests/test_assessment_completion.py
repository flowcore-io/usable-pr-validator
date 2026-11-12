import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from test_validation_contract import ROOT, load

REPORT = "# PR Validation Report\n## Validation Outcome\n- **Status**: FAIL\n- **Critical Issues**: 0\n"


def events(report, reason="stop"):
    return [
        {"type": "step_start", "part": {"type": "step-start", "messageID": "final"}},
        {"type": "text", "part": {"type": "text", "messageID": "final", "text": report, "time": {"end": 1}}},
        {"type": "step_finish", "part": {"type": "step-finish", "messageID": "final", "reason": reason}},
    ]


class AssessmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parser = load("completion_parser", "parse-validation-report.py")
        cls.extractor = load("completion_extractor", "extract-provider-report.py")

    def test_opt_in_requires_complete_but_preserves_legitimate_fail(self):
        self.assertEqual(self.parser.parse_report(REPORT)["status"], "failed")
        for status in ("", "- **Assessment**: INCOMPLETE\n", "- **Assessment**: COMPLETE\n" * 2):
            with self.subTest(status=status), self.assertRaises(ValueError):
                self.parser.parse_report(REPORT + status, require_complete=True)
        result = self.parser.parse_report(REPORT + "- **Assessment**: COMPLETE\n", require_complete=True)
        self.assertFalse(result["passed"])
        self.assertEqual(result["critical_issues"], 0)

    def test_annotated_or_malformed_duplicate_assessment_cannot_bypass_completion(self):
        for duplicate in ("- **Assessment**: INCOMPLETE (evidence missing)",
                          "- **Assessment**: unknown", "- **Assessment**:",
                          "- Assessment: INCOMPLETE", "* **Assessment**: INCOMPLETE"):
            with self.subTest(duplicate=duplicate), self.assertRaises(ValueError):
                self.parser.parse_report(REPORT + "- **Assessment**: COMPLETE\n" + duplicate + "\n", require_complete=True)

    def test_terminal_reason_and_numeric_diagnostics_never_echo_arbitrary_data(self):
        for reason in (None, "length", "content-filter", "unknown", "PRIVATE_CANARY", ["PRIVATE_CANARY"]):
            with self.subTest(reason=reason), self.assertRaises(self.extractor.ExtractionError):
                self.extractor.extract_with_diagnostics("opencode", "\n".join(map(json.dumps, events(REPORT, reason))), require_stop_reason=True)
        records = events(REPORT)
        records[-1]["part"].update(tokens={"input": 42, "output": "PRIVATE_CANARY", "reasoning": True, "total": -1, "cache": {"read": 3, "write": 10**100}}, cost=float("inf"))
        _, metadata = self.extractor.extract_with_diagnostics("opencode", "\n".join(map(json.dumps, records)), require_stop_reason=True)
        self.assertNotIn("PRIVATE_CANARY", json.dumps(metadata))
        self.assertEqual(metadata["steps"][0]["tokens"], {"input": 42, "output": None, "reasoning": None, "total": None})
        self.assertEqual(metadata["steps"][0]["cache"], {"read": 3, "write": None})
        self.assertIsNone(metadata["steps"][0]["cost"])

    def run_review(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "prompt").write_text("synthetic review")
            for state in ("INCOMPLETE", "COMPLETE"):
                (root / state).write_text("\n".join(map(json.dumps, events(REPORT + f"- **Assessment**: {state}\n"))))
            fake = root / "opencode"
            fake.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ["PROBE_ROOT"])
model = sys.argv[sys.argv.index("-m") + 1]
with (root / "calls").open("a") as f: f.write(model + "\\n")
count = len((root / "calls").read_text().splitlines())
complete = os.environ["PROBE_MODE"] == "complete" or "fallback" in model or (os.environ["PROBE_MODE"] == "retry" and count > 1)
sys.stdout.write((root / ("COMPLETE" if complete else "INCOMPLETE")).read_text())
''')
            fake.chmod(0o700)
            script = f'''set -euo pipefail
export ACTION_PATH={ROOT}
export VALIDATE_SH_LIBRARY_ONLY=true MAX_RETRIES=1 VALIDATION_TIMEOUT_MINUTES=1 REQUIRE_COMPLETE_ASSESSMENT=true
source {ROOT}/scripts/validate.sh
rc=0
run_opencode {root}/prompt openrouter openai/primary || rc=$?
if [ "$rc" = 2 ]; then run_opencode {root}/prompt openrouter openai/fallback; else exit "$rc"; fi
'''
            result = subprocess.run(["bash", "-c", script], env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}", "PROBE_ROOT": str(root), "PROBE_MODE": mode}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return (root / "calls").read_text().splitlines()

    def test_incomplete_assessment_uses_retry(self):
        self.assertEqual(self.run_review("retry"), ["openrouter/openai/primary"] * 2)

    def test_exhausted_incomplete_assessment_uses_existing_fallback(self):
        self.assertEqual(self.run_review("fallback"), ["openrouter/openai/primary"] * 2 + ["openrouter/openai/fallback"])

    def test_completed_failed_verdict_is_not_retried_or_fallbacked(self):
        self.assertEqual(self.run_review("complete"), ["openrouter/openai/primary"])
