import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
FORMATTER = ROOT / "scripts" / "format-pr-comment.cjs"


def options(report):
    return {
        "report": report,
        "title": "Security Validation",
        "validationStatus": "passed",
        "validationOutcome": "success",
        "criticalIssues": "0",
        "groundingStatus": "complete",
        "modelInfo": "fixture/model",
        "standardsSource": "https://example.invalid/mcp",
        "commit": "a" * 40,
        "actor": "fixture",
        "runUrl": "https://github.com/example/project/actions/runs/1",
        "artifactUrl": "https://github.com/example/project/actions/runs/1/artifacts/2",
        "artifactName": "pr-validation-security",
    }


def format_comment(value):
    script = """const fs = require('fs');
const {formatPrComment} = require(process.argv[1]);
process.stdout.write(JSON.stringify(formatPrComment(JSON.parse(fs.readFileSync(0, 'utf8')))));
"""
    result = subprocess.run(
        ["node", "-e", script, str(FORMATTER)],
        input=json.dumps(value), text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout)


class ReportPublicationTests(unittest.TestCase):
    def test_short_report_is_complete_with_exact_artifact_link(self):
        report = "# PR Validation Report\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 0\n"
        result = format_comment(options(report))
        self.assertFalse(result["truncated"])
        self.assertIn(report, result["body"])
        self.assertIn("**Action result: PASSED**", result["body"])
        self.assertIn("/artifacts/2", result["body"])
        self.assertEqual(result["marker"], "<!-- usable-pr-validator:security-validation -->")

    def test_large_failed_report_preserves_failure_and_does_not_modify_source(self):
        report = "# PR Validation Report\n" + "Finding evidence.\n" * 15000 + "FINAL_FINDING"
        before = hashlib.sha256(report.encode()).hexdigest()
        value = options(report)
        value.update(validationStatus="failed", criticalIssues="7")
        result = format_comment(value)
        self.assertTrue(result["truncated"])
        self.assertLessEqual(len(result["body"].encode()), 60000)
        self.assertIn("**Action result: FAILED** · Critical issues: 7", result["body"])
        self.assertIn("consult the full report artifact", result["body"])
        self.assertEqual(hashlib.sha256(value["report"].encode()).hexdigest(), before)
        self.assertTrue(value["report"].endswith("FINAL_FINDING"))

    def test_multibyte_reports_and_metadata_stay_within_the_complete_comment_budget(self):
        value = options("🙂 Føroyskt " * 20000)
        for key in ["title", "modelInfo", "standardsSource", "actor", "artifactName"]:
            value[key] = "🦀\n" * 30000
        result = format_comment(value)
        self.assertLessEqual(len(result["body"].encode()), 60000)
        self.assertNotIn("\ufffd", result["body"])
        self.assertTrue(result["body"].endswith("</details>"))

    def test_failed_or_missing_step_cannot_display_a_pass_from_stale_outputs(self):
        for outcome in ["failure", "cancelled", "skipped", ""]:
            with self.subTest(outcome=outcome):
                value = options("Report")
                value.update(validationOutcome=outcome, artifactUrl="")
                result = format_comment(value)
                self.assertIn("**Action result: ERROR**", result["body"])
                self.assertIn("Report artifact link unavailable", result["body"])
                self.assertNotIn("[Full validated report artifact]", result["body"])

    def test_action_posts_bounded_formatter_output_and_uploads_full_report_first(self):
        action = (ROOT / "action.yml").read_text()
        self.assertLess(action.index("- name: Upload Validation Report"), action.index("- name: Post PR Comment"))
        block = action.split("    - name: Post PR Comment\n", 1)[1].split("    - name: Cleanup Secrets\n", 1)[0]
        script = block.split("        script: |\n", 1)[1]
        script = "\n".join(line[10:] if line.startswith("          ") else line for line in script.splitlines())
        report = "# PR Validation Report\n" + "Evidence\n" * 20000
        harness = r"""
const fs = require('fs');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
let posted;
const fakeFs = {existsSync: () => true, readFileSync: () => input.report};
const fakeGithub = {rest: {issues: {
  listComments: async () => ({data: []}),
  createComment: async (value) => { posted = value.body; },
}}};
const localRequire = name => name === 'fs' ? fakeFs : require(name);
const context = {repo: {owner: 'example', repo: 'project'}, runId: 1, actor: 'fixture',
  payload: {pull_request: {head: {sha: 'a'.repeat(40)}, number: 7}}};
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
new AsyncFunction('require', 'github', 'context', 'console', input.script)(
  localRequire, fakeGithub, context, {log() {}}
).then(() => process.stdout.write(JSON.stringify({posted, report: input.report})));
"""
        env = dict(os.environ, VALIDATOR_ACTION_PATH=str(ROOT), VALIDATOR_COMMENT_MODE="update",
                   VALIDATOR_COMMENT_TITLE="Security Validation", VALIDATOR_STATUS="failed",
                   VALIDATOR_STEP_OUTCOME="success", VALIDATOR_CRITICAL_ISSUES="2",
                   VALIDATOR_GROUNDING_STATUS="complete", VALIDATOR_ARTIFACT_URL="https://example.invalid/artifact/2",
                   VALIDATOR_ARTIFACT_NAME="full-report", GITHUB_SERVER_URL="https://github.com")
        completed = subprocess.run(["node", "-e", harness], input=json.dumps({"script": script, "report": report}),
                                   text=True, capture_output=True, env=env, check=True)
        result = json.loads(completed.stdout)
        self.assertLessEqual(len(result["posted"].encode()), 60000)
        self.assertIn("**Action result: FAILED**", result["posted"])
        self.assertIn("https://example.invalid/artifact/2", result["posted"])
        self.assertEqual(result["report"], report)

    def test_large_report_completes_actual_orchestration_without_sigpipe(self):
        report = "# PR Validation Report\n\n## Summary\nFixture.\n\n## Suggestions\n" + "Evidence " * 12 + "\n"
        report += ("- " + "evidence " * 12 + "\n") * 20000
        report += "\nFINAL_ARTIFACT_SENTINEL\n\n## Validation Outcome\n- **Status**: PASS ✅\n- **Critical Issues**: 0\n"
        events = [
            {"type": "step_start", "part": {"type": "step-start", "messageID": "final"}},
            {"type": "text", "part": {"type": "text", "messageID": "final", "text": report, "time": {"end": 1}}},
            {"type": "step_finish", "part": {"type": "step-finish", "messageID": "final", "reason": "stop"}},
        ]
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            provider = temp / "provider.jsonl"
            provider.write_text("\n".join(json.dumps(event) for event in events) + "\n")
            output = temp / "outputs.txt"
            required = temp / "required.txt"
            ledger = temp / "ledger.jsonl"
            required.write_text("")
            ledger.write_text("")
            env = dict(os.environ, ACTION_PATH=str(ROOT), VALIDATE_SH_LIBRARY_ONLY="true",
                       PROMPT_FILE=str(provider), FIXTURE_PROVIDER=str(provider), GITHUB_OUTPUT=str(output),
                       USABLE_REQUIRED_FRAGMENTS_FILE=str(required), USABLE_GROUNDING_LEDGER=str(ledger),
                       GROUNDING_PREFETCH_FAILED="false", PROVIDER="opencode")
            script = r'''
set -euo pipefail
source "$ACTION_PATH/scripts/validate.sh"
verify_git_refs() { return 0; }
prepare_prompt() { printf '%s\n' "$PROMPT_FILE"; }
run_opencode() { cp "$FIXTURE_PROVIDER" /tmp/validation-full-output.md; }
main
'''
            try:
                completed = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertIn("validation_status=passed", output.read_text())
                full = Path("/tmp/validation-report.md").read_text()
                self.assertIn("FINAL_ARTIFACT_SENTINEL", full)
                self.assertGreater(len(full), 2_000_000)
                self.assertNotIn("FINAL_ARTIFACT_SENTINEL", completed.stdout)
            finally:
                Path("/tmp/validation-report.md").unlink(missing_ok=True)
                Path("/tmp/validation-full-output.md").unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
