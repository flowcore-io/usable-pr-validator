"""Synthetic tests of the public/private report boundary; no provider credentials."""

import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).parents[1]
SENTINEL = "PRIVATE_SYNTHETIC_REPORT_CANARY_7a21"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def private_report(status="PASS", count=0):
    return f"""# PR Validation Report
## Summary
{SENTINEL}
## Evidence
> {SENTINEL}
![hidden](https://example.invalid/{SENTINEL})
<!-- {SENTINEL} -->
## Validation Outcome
- **Status**: {status}
- **Critical Issues**: {count}
## Extra material
{SENTINEL}
"""


class ReportPrivacyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.publisher = load("publisher", "publish-validation-report.py")
        cls.extractor = load("extractor", "extract-provider-report.py")
        cls.parser = load("parser", "parse-validation-report.py")

    def test_default_is_fixed_metadata_not_assistant_markdown(self):
        for status, count in [("PASS", 0), ("FAIL", 0), ("FAIL", 2)]:
            with self.subTest(status=status, count=count):
                public = self.publisher.render(private_report(status, count), "complete")
                self.assertNotIn(SENTINEL, public)
                self.assertNotIn("example.invalid", public)
                self.assertEqual(self.parser.parse_report(public), {
                    "status": "passed" if status == "PASS" else "failed",
                    "passed": status == "PASS", "critical_issues": count,
                })
                self.assertIn("COMPLETE", public)

    def test_both_provider_contracts_use_same_metadata_boundary(self):
        answer = private_report()
        opencode = "\n".join(json.dumps(event) for event in [
            {"type": "step_start", "part": {"type": "step-start", "messageID": "final"}},
            {"type": "text", "part": {"type": "text", "messageID": "final", "text": answer, "time": {"end": 1}}},
            {"type": "step_finish", "part": {"type": "step-finish", "messageID": "final", "reason": "stop"}},
        ])
        for provider, payload in [("opencode", opencode), ("gemini", json.dumps({"response": answer}))]:
            with self.subTest(provider=provider):
                extracted = self.extractor.extract(provider, payload)
                self.assertIn(SENTINEL, extracted)
                self.assertNotIn(SENTINEL, self.publisher.render(extracted, "not-required"))

    def test_full_report_requires_exact_explicit_opt_in(self):
        self.assertIn(SENTINEL, self.publisher.render(private_report(), "complete", "full"))
        for mode in ["", "FULL", "metadata", SENTINEL, "full\n"]:
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.publisher.render(private_report(), "complete", mode)

    def test_incomplete_grounding_cannot_publish_pass(self):
        for mode in ["metadata-only", "full"]:
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.publisher.render(private_report(), "incomplete", mode)
        public = self.publisher.render(private_report("FAIL", 1), "incomplete")
        self.assertIn("INCOMPLETE", public)
        self.assertNotIn(SENTINEL, public)

    def test_unknown_grounding_invalid_counts_and_invalid_report_rejected(self):
        for text, status in [(private_report(), SENTINEL), (private_report("FAIL", 1001), "complete"),
                             (private_report("FAIL", -1), "complete"), (SENTINEL, "complete")]:
            with self.subTest(status=status), self.assertRaises(ValueError):
                self.publisher.render(text, status)

    def test_cli_failure_is_generic_and_does_not_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "private.md"
            target = Path(directory) / "public.md"
            for payload in [SENTINEL.encode(), b"\xff" + SENTINEL.encode(), b"x" * (1024 * 1024 + 1)]:
                source.write_bytes(payload)
                result = subprocess.run(["python3", str(ROOT / "scripts/publish-validation-report.py"),
                                         "--report", str(source), "--output", str(target),
                                         "--grounding-status", "complete"], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(SENTINEL, result.stdout + result.stderr)
                self.assertNotIn(str(source), result.stdout + result.stderr)
                self.assertFalse(target.exists())

    def test_cli_publishes_only_owner_readable_metadata_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "private.md"
            target = Path(directory) / "public.md"
            source.write_text(private_report())
            result = subprocess.run(["python3", str(ROOT / "scripts/publish-validation-report.py"),
                                     "--report", str(source), "--output", str(target),
                                     "--grounding-status", "not-required"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(SENTINEL, target.read_text() + result.stdout + result.stderr)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(sorted(path.name for path in Path(directory).iterdir()), ["private.md", "public.md"])

    def test_metadata_comment_ignores_arbitrary_report_text(self):
        options = {"title": "Synthetic validation", "report": private_report(), "visibility": "metadata-only",
                   "validationStatus": "passed", "validationOutcome": "success", "criticalIssues": "0",
                   "groundingStatus": "complete", "runUrl": "https://github.com/example/repo/actions/runs/1"}
        script = "const f=require('./scripts/format-pr-comment.cjs'); process.stdout.write(JSON.stringify(f.formatPrComment(JSON.parse(process.argv[1]))));"
        result = subprocess.run(["node", "-e", script, json.dumps(options)], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)
        self.assertIn("PASSED", json.loads(result.stdout)["body"])

    def test_actual_comment_step_does_not_log_api_error_request_bodies(self):
        action = (ROOT / "action.yml").read_text()
        comment = action.split("    - name: Post PR Comment\n", 1)[1].split("\n    - name:", 1)[0]
        script = textwrap.dedent(comment.split("        script: |\n", 1)[1])
        harness = """const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
const messages = [];
const core = {info: message => messages.push(message), setFailed: message => messages.push(message)};
const github = {rest: {issues: {
  listComments: async () => ({data: []}),
  createComment: async request => {throw new Error(process.env.CANARY + JSON.stringify(request));}
}}};
const context = {repo: {owner: 'example', repo: 'repo'}, payload: {pull_request: {number: 1}}};
new AsyncFunction('require', 'github', 'context', 'core', process.argv[1])(require, github, context, core)
  .then(() => process.stdout.write(JSON.stringify(messages)));
"""
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.md"
            report.write_text(private_report())
            for visibility in ["metadata-only", "full"]:
                with self.subTest(visibility=visibility):
                    result = subprocess.run(["node", "-e", harness, script], env={**os.environ,
                        "ACTION_PATH": str(ROOT), "REPORT_PATH": str(report), "CANARY": SENTINEL,
                        "REPORT_VISIBILITY": visibility, "COMMENT_MODE": "new",
                        "VALIDATION_STATUS": "passed", "VALIDATION_OUTCOME": "success",
                        "CRITICAL_ISSUES": "0", "GROUNDING_STATUS": "complete"},
                        capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout), ["Validation comment publication failed."])
                    self.assertNotIn(SENTINEL, result.stdout + result.stderr)

    def test_readiness_requires_publication_and_error_count_matches_report(self):
        with tempfile.TemporaryDirectory() as directory:
            public = Path(directory) / "report.md"
            public.write_text(SENTINEL)
            outputs = Path(directory) / "outputs"
            script = '''source "$ACTION_PATH/scripts/validate.sh"
write_outputs error false 0 incomplete
grounding_status=not-required
publish_safe_error_report "$CANARY"
write_outputs error false 0 "$grounding_status"
'''
            result = subprocess.run(["bash", "-c", script], env={**os.environ,
                "ACTION_PATH": str(ROOT), "VALIDATE_SH_LIBRARY_ONLY": "true", "CANARY": SENTINEL,
                "VALIDATION_REPORT_PATH": str(public), "GITHUB_OUTPUT": str(outputs)},
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual([line for line in outputs.read_text().splitlines() if line.startswith("report_ready=")],
                             ["report_ready=false", "report_ready=true"])
            self.assertEqual([line for line in outputs.read_text().splitlines() if line.startswith("critical_issues=")],
                             ["critical_issues=0", "critical_issues=1"])
            self.assertEqual(self.parser.parse_report(public.read_text())["critical_issues"], 1)
            self.assertNotIn(SENTINEL, public.read_text() + result.stdout + result.stderr + outputs.read_text())

    def test_workflow_diagnostics_do_not_dump_transcripts_if_cleanup_fails(self):
        workflow = (ROOT / ".github/workflows/test.yml").read_text()
        for name in ["Debug Test Results", "Debug Documentation Results", "Verify Override Context Was Included"]:
            step = workflow.split(f"      - name: {name}\n", 1)[1]
            lines = []
            for line in step.split("        run: |\n", 1)[1].splitlines():
                if line.strip() and not line.startswith("          "):
                    break
                lines.append(line)
            script = textwrap.dedent("\n".join(lines))
            script = re.sub(r"\$\{\{ steps\.[a-z-]+\.outcome }}", "failure", script)
            with self.subTest(step=name), tempfile.TemporaryDirectory() as directory:
                for filename in ["validation-full-output.md", "validation-prompt.txt"]:
                    (Path(directory) / filename).write_text(SENTINEL)
                # Retain private files to simulate failed cleanup. Execute the
                # workflow's actual diagnostics in an isolated temporary path.
                result = subprocess.run(["bash", "-c", script.replace("/tmp/", directory + "/")],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("failure", result.stdout)
                self.assertNotIn(SENTINEL, result.stdout + result.stderr)

    def test_full_comments_remain_utf8_bounded_and_keep_result_and_link(self):
        options = {"title": "Synthetic validation", "report": "🧪" * 40000, "visibility": "full",
                   "validationStatus": "failed", "validationOutcome": "success", "criticalIssues": "2",
                   "groundingStatus": "complete", "runUrl": "https://github.com/example/repo/actions/runs/1",
                   "artifactUrl": "https://github.com/example/repo/actions/runs/1/artifacts/2"}
        script = "const f=require('./scripts/format-pr-comment.cjs'); process.stdout.write(JSON.stringify(f.formatPrComment(JSON.parse(require('fs').readFileSync(0,'utf8')))));"
        result = subprocess.run(["node", "-e", script], input=json.dumps(options), cwd=ROOT,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        comment = json.loads(result.stdout)
        self.assertTrue(comment["truncated"])
        self.assertLessEqual(len(comment["body"].encode()), 60000)
        self.assertIn("Action result: FAILED", comment["body"])
        self.assertIn(options["artifactUrl"], comment["body"])
        self.assertNotIn("\ufffd", comment["body"])

    def test_symlink_and_non_regular_private_input_is_not_read(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "private.md"
            source.write_text(SENTINEL)
            link = Path(directory) / "link.md"
            link.symlink_to(source)
            fifo = Path(directory) / "fifo"
            os.mkfifo(fifo)
            for path in [link, fifo]:
                with self.subTest(path=path), self.assertRaises((ValueError, OSError)):
                    self.publisher.read_private(path)

    def test_two_invocations_never_share_report_or_publish_previous_failure(self):
        action = (ROOT / "action.yml").read_text()
        initialize = action.split("    - name: Initialize report publication\n", 1)[1].split("\n    - name:", 1)[0]
        script = textwrap.dedent(initialize.split("      run: |\n", 1)[1])
        self.assertEqual(action.count("steps.validate.outputs.report_ready == 'true'"), 2)
        self.assertLess(action.index("    - name: Upload Validation Report"), action.index("    - name: Post PR Comment"))
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for index in range(2):
                output = Path(directory) / f"outputs-{index}"
                result = subprocess.run(["bash", "-c", script], env={**os.environ,
                    "REPORT_VISIBILITY": "metadata-only", "RUNNER_TEMP": directory, "GITHUB_OUTPUT": str(output)},
                    capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                values = dict(line.split("=", 1) for line in output.read_text().splitlines())
                current = Path(values["report_path"])
                self.assertEqual(current.parent.stat().st_mode & 0o777, 0o700)
                self.assertFalse(current.exists())
                paths.append(current)
                if index == 0:
                    current.write_text(SENTINEL)
            # Second invocation fails in setup and never reaches validation.
            self.assertNotEqual(paths[0], paths[1])
            self.assertFalse(paths[1].exists())
            self.assertEqual(paths[0].read_text(), SENTINEL)

    def test_actual_orchestration_never_logs_or_publishes_private_prose_by_default(self):
        for provider in ["opencode", "gemini"]:
            for status, count, visibility in [("PASS", 0, "metadata-only"), ("FAIL", 0, "metadata-only"),
                                               ("FAIL", 2, "metadata-only"), ("PASS", 0, "full"),
                                               (None, 1, "metadata-only")]:
                with self.subTest(provider=provider, status=status, count=count, visibility=visibility), tempfile.TemporaryDirectory() as directory:
                    private = Path(directory)
                    report = private_report(status, count)
                    if provider == "gemini":
                        payload = json.dumps({"response": report})
                    else:
                        payload = "\n".join(json.dumps(event) for event in [
                            {"type": "step_start", "part": {"type": "step-start", "messageID": "final"}},
                            {"type": "text", "part": {"type": "text", "messageID": "final", "text": report, "time": {"end": 1}}},
                            {"type": "step_finish", "part": {"type": "step-finish", "messageID": "final", "reason": "stop"}},
                        ])
                    fixture = private / "provider.json"
                    fixture.write_text(payload)
                    script_path = private / "validate.sh"
                    script_path.write_text((ROOT / "scripts/validate.sh").read_text().replace("/tmp/", directory + "/"))
                    prompt = private / "prompt.md"
                    prompt.write_text("Synthetic review prompt.")
                    required = private / "required"
                    required.write_text("")
                    ledger = private / "ledger"
                    ledger.write_text("")
                    outputs = private / "outputs"
                    public = private / "public.md"
                    script = '''source "$VALIDATOR_TEST_SCRIPT"
verify_git_refs() { return 0; }
prepare_prompt() { printf '%s\\n' "$PROMPT_FILE"; }
run_opencode() { if [ "$VALIDATOR_TEST_MISSING" = true ]; then return 0; fi; cp "$VALIDATOR_TEST_FIXTURE" "$VALIDATOR_TEST_TRANSCRIPT"; }
run_gemini() { run_opencode; }
main
'''
                    result = subprocess.run(["bash", "-c", script], env={**os.environ,
                        "VALIDATE_SH_LIBRARY_ONLY": "true", "ACTION_PATH": str(ROOT),
                        "VALIDATOR_TEST_SCRIPT": str(script_path), "VALIDATOR_TEST_FIXTURE": str(fixture),
                        "VALIDATOR_TEST_MISSING": "true" if status is None else "false",
                        "VALIDATOR_TEST_TRANSCRIPT": str(private / "validation-full-output.md"),
                        "PROMPT_FILE": str(prompt), "PROVIDER": provider, "REPORT_VISIBILITY": visibility,
                        "VALIDATION_REPORT_PATH": str(public), "GITHUB_OUTPUT": str(outputs),
                        "USABLE_REQUIRED_FRAGMENTS_FILE": str(required), "USABLE_GROUNDING_LEDGER": str(ledger)},
                        capture_output=True, text=True)
                    self.assertEqual(result.returncode, 1 if status is None else 0, result.stderr)
                    published = public.read_text()
                    self.assertNotIn(SENTINEL, result.stdout + result.stderr + outputs.read_text())
                    if visibility == "metadata-only":
                        self.assertNotIn(SENTINEL, published)
                    else:
                        self.assertIn(SENTINEL, published)
                    self.assertIn("report_ready=true", outputs.read_text())
                    self.assertEqual(self.parser.parse_report(published)["critical_issues"], count)
                    self.assertEqual(list(private.glob("validation-report.candidate.*")), [])


if __name__ == "__main__":
    unittest.main()
