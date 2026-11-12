import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
CANARY = "SYNTHETIC_PRIVATE_ATTEMPT_5c3a"


class AttemptCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        root = Path(cls.directory.name)
        cls.key, cls.cert = root / "private.pem", root / "cert.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-keyout", str(cls.key), "-out", str(cls.cert), "-days", "1", "-subj", "/CN=Synthetic attempt test/"], check=True, capture_output=True)
        der = subprocess.check_output(["openssl", "x509", "-in", str(cls.cert), "-outform", "DER"])
        cls.env = {**os.environ, "ENCRYPTED_ATTEMPT_RECIPIENT": cls.cert.read_text(), "ENCRYPTED_ATTEMPT_RECIPIENT_SHA256": hashlib.sha256(der).hexdigest(), "UNRELATED_SECRET_MUST_NOT_COLLECT": CANARY + "_ENV"}

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def run_capture(self, root, attempt, changes=None):
        return subprocess.run(["python3", str(ROOT / "scripts/capture-provider-attempt.py"), "--prompt", str(root / "prompt"), "--stdout", str(root / "stdout"), "--stderr", str(root / "stderr"), "--output", str(root / f"attempt-{attempt}.cms"), "--provider", "opencode", "--model", "synthetic", "--attempt", str(attempt), "--exit-code", "0"], env={**self.env, **(changes or {})}, text=True, capture_output=True)

    def test_attempts_survive_source_overwrite_and_contain_only_explicit_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payloads = {"prompt": CANARY.encode(), "stdout": b'{"type":"text"}', "stderr": b"synthetic stderr"}
            for name, data in payloads.items():
                (root / name).write_bytes(data)
            for attempt in (1, 2):
                result = self.run_capture(root, attempt)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn(CANARY, result.stdout + result.stderr)
                self.assertEqual((root / f"attempt-{attempt}.cms").stat().st_mode & 0o777, 0o600)
                (root / "stdout").write_bytes(b"replacement")
            for attempt in (1, 2):
                plain = subprocess.check_output(["openssl", "cms", "-decrypt", "-binary", "-inform", "DER", "-in", str(root / f"attempt-{attempt}.cms"), "-recip", str(self.cert), "-inkey", str(self.key)])
                data = json.loads(plain)
                self.assertEqual(data["attempt"], attempt)
                self.assertNotIn((CANARY + "_ENV").encode(), plain)
                self.assertEqual(base64.b64decode(data["inputs"]["prompt"]["base64"]), payloads["prompt"])
                self.assertEqual(base64.b64decode(data["inputs"]["stdout"]["base64"]), payloads["stdout"] if attempt == 1 else b"replacement")
                self.assertEqual(data["inputs"]["prompt"]["sha256"], hashlib.sha256(payloads["prompt"]).hexdigest())

    def test_missing_invalid_or_unreadable_capture_fails_without_plaintext(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("prompt", "stdout", "stderr"):
                (root / name).write_text(CANARY)
            for changes in ({"ENCRYPTED_ATTEMPT_RECIPIENT_SHA256": "0" * 64}, {"ENCRYPTED_ATTEMPT_RECIPIENT": ""}):
                result = self.run_capture(root, 1, changes)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(CANARY, result.stdout + result.stderr)
                self.assertFalse((root / "attempt-1.cms").exists())
            (root / "stderr").unlink()
            (root / "stderr").symlink_to(root / "prompt")
            result = self.run_capture(root, 1)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(CANARY, result.stdout + result.stderr)
            self.assertFalse((root / "attempt-1.cms").exists())

    def test_orchestrator_captures_each_attempt_before_retry_and_failure_blocks(self):
        from test_assessment_completion import events, REPORT
        for valid in (True, False):
            with self.subTest(valid=valid), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "prompt").write_text(CANARY)
                for status in ("INCOMPLETE", "COMPLETE"):
                    (root / status).write_text("\n".join(map(json.dumps, events(REPORT + f"- **Assessment**: {status}\n"))))
                fake = root / "opencode"
                fake.write_text("#!/usr/bin/env python3\nimport pathlib,os,sys\nr=pathlib.Path(os.environ['PROBE_ROOT'])\np=r/'count'\nn=int(p.read_text())+1 if p.exists() else 1\np.write_text(str(n))\nsys.stdout.write((r/('COMPLETE' if n>1 else 'INCOMPLETE')).read_text())\n")
                fake.chmod(0o700)
                script = f"""set -euo pipefail
export ACTION_PATH={ROOT} VALIDATE_SH_LIBRARY_ONLY=true
export REQUIRE_COMPLETE_ASSESSMENT=true MAX_RETRIES=1 VALIDATION_TIMEOUT_MINUTES=1
export VALIDATION_REPORT_PATH={root}/report.md GITHUB_OUTPUT={root}/outputs
source {ROOT}/scripts/validate.sh
run_opencode {root}/prompt openrouter synthetic
"""
                env = {**self.env, "PATH": f"{root}:{os.environ['PATH']}", "PROBE_ROOT": str(root)}
                if not valid:
                    env["ENCRYPTED_ATTEMPT_RECIPIENT_SHA256"] = "0" * 64
                result = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
                self.assertNotIn(CANARY, result.stdout + result.stderr)
                self.assertEqual(result.returncode == 0, valid, result.stderr)
                self.assertEqual((root / "count").read_text(), "2" if valid else "1")
                archives = sorted((root / "report.md.attempts").glob("*.cms"))
                self.assertEqual(len(archives), 2 if valid else 0)
                for archive, status in zip(archives, ("INCOMPLETE", "COMPLETE")):
                    plain = subprocess.check_output(["openssl", "cms", "-decrypt", "-binary", "-inform", "DER", "-in", str(archive), "-recip", str(self.cert), "-inkey", str(self.key)])
                    bundle = json.loads(plain)
                    self.assertIn(f"- **Assessment**: {status}", base64.b64decode(bundle["inputs"]["stdout"]["base64"]).decode())
