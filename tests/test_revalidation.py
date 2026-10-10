"""Synthetic event-shape and immutable release-pin regressions."""

import importlib.util
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).parents[1]


def event_value(event, path):
    value = event
    for key in path.removeprefix("github.event.").split("."):
        if key == "*":
            continue
        if isinstance(value, list):
            value = [item.get(key, "") for item in value]
        else:
            value = value.get(key, {}) if isinstance(value, dict) else {}
    return value if value != {} else ""


def validation_env(event):
    # Evaluate only the path fallback/join expressions actually wired to Run
    # Validation. Unexpected expression syntax fails rather than being ignored.
    action = (ROOT / "action.yml").read_text()
    block = action.split("    - name: Run Validation\n", 1)[1].split("      run: |", 1)[0]
    result = {}
    for key, expression in re.findall(r"^        (PR_\w+): \$\{\{ (.+) \}\}$", block, re.MULTILINE):
        values = []
        for part in expression.split(" || "):
            joined = re.fullmatch(r"join\((.+), ', '\)", part)
            path = joined.group(1) if joined else part
            if not re.fullmatch(r"github\.event\.[\w.*]+", path):
                raise AssertionError(expression)
            value = event_value(event, path)
            # Join before fallback: missing wildcard paths may be empty arrays
            # in Actions, and arrays themselves are truthy there.
            values.append(", ".join(value) if joined and isinstance(value, list) else value)
        result[key] = str(next((value for value in values if value), ""))
    return result


class RevalidationContextTests(unittest.TestCase):
    def test_issue_comment_and_pull_request_populate_context_and_placeholders(self):
        pr = {"number": 56, "title": "Fix context", "body": "Description\nwith another line",
              "html_url": "https://github.com/flowcore-io/usable-pr-validator/pull/56",
              "user": {"login": "author"}, "labels": [{"name": "bug"}, {"name": "review"}]}
        expected = dict(PR_NUMBER="56", PR_TITLE=pr["title"], PR_DESCRIPTION=pr["body"],
                        PR_URL=pr["html_url"], PR_AUTHOR="author", PR_LABELS="bug, review")
        for event in [{"issue": pr, "comment": {"body": "@usable recheck"}},
                      {"pull_request": pr}, {"pull_request": pr, "issue": {"title": "wrong"}}]:
            with self.subTest(event=event):
                values = validation_env(event)
                self.assertEqual(values, expected)
                env = dict(os.environ, **values, ACTION_PATH=str(ROOT), BASE_BRANCH="main", HEAD_BRANCH="fix",
                           VALIDATE_SH_LIBRARY_ONLY="true")
                # Exercise real prompt rendering, stubbing only git diff discovery.
                script = '''source "$ACTION_PATH/scripts/validate.sh"
generate_diff_summary() { printf 'Synthetic diff'; }
prepare_prompt <(printf '{{PR_CONTEXT}}\n{{PR_NUMBER}}|{{PR_TITLE}}|{{PR_DESCRIPTION}}|{{PR_URL}}|{{PR_AUTHOR}}|{{PR_LABELS}}')
cat /tmp/validation-prompt.txt
'''
                rendered = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, check=True).stdout
                self.assertIn("**PR #56**: Fix context", rendered)
                self.assertIn("**Labels**: bug, review", rendered)
                for value in expected.values():
                    self.assertIn(value, rendered)
                self.assertNotIn("{{PR_", rendered)

    def test_empty_labels_and_description_are_supported(self):
        values = validation_env({"issue": {"number": 1, "body": None, "labels": []}})
        self.assertEqual(values["PR_LABELS"], "")
        self.assertEqual(values["PR_NUMBER"], "1")


class RevalidationPinTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("pin_policy", ROOT / "scripts/check-revalidation-pin.py")
        cls.policy = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.policy)

    def test_latest_release_commit_and_version_are_both_required(self):
        sha = "a" * 40
        workflow = f"        uses: flowcore-io/usable-pr-validator@{sha} # v2.2.9\n"
        self.policy.check(workflow, "v2.2.9", sha)
        for tag, commit in [("v2.2.10", sha), ("v2.2.9", "b" * 40), ("latest", sha), ("v2.2.9", "short")]:
            with self.subTest(tag=tag, commit=commit), self.assertRaises(ValueError):
                self.policy.check(workflow, tag, commit)
        for unsafe in ["        uses: ./\n", workflow + workflow,
                       workflow.replace(sha, "v2.2.9")]:
            with self.subTest(workflow=unsafe), self.assertRaises(ValueError):
                self.policy.check(unsafe, "v2.2.9", sha)
