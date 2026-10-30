"""CLI-only tests with disposable keys and synthetic report canaries."""
import hashlib
from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
CANARY = "CONFIDENTIAL_SYNTHETIC_FINDING_34bf"
REPORT = ("# PR Validation Report\n## Summary\n" + CANARY +
          "\n## Validation Outcome\n- **Status**: FAIL\n- **Critical Issues**: 1\n")


class EncryptedReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.root = Path(cls.directory.name)
        cls.key = cls.root / "private.pem"
        cls.cert = cls.root / "recipient.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes",
                        "-keyout", str(cls.key), "-out", str(cls.cert), "-days", "1",
                        "-subj", "/CN=Synthetic test/"], check=True, capture_output=True)
        der = subprocess.check_output(["openssl", "x509", "-in", str(cls.cert), "-outform", "DER"])
        cls.env = {**os.environ, "ENCRYPTED_REPORT_RECIPIENT": cls.cert.read_text(),
                   "ENCRYPTED_REPORT_RECIPIENT_SHA256": hashlib.sha256(der).hexdigest()}

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def run_cli(self, source, target, env=None):
        return subprocess.run(["python3", str(ROOT / "scripts/encrypt-validation-report.py"),
                               "--report", str(source), "--output", str(target)],
                              env=env or self.env, capture_output=True, text=True)

    def test_authenticated_round_trip_and_tampering(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / "report", Path(directory) / "cipher.cms"
            source.write_text(REPORT)
            result = self.run_cli(source, target)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(CANARY, result.stdout + result.stderr)
            self.assertNotIn(CANARY.encode(), target.read_bytes())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            command = ["openssl", "cms", "-decrypt", "-binary", "-inform", "DER",
                       "-in", str(target), "-recip", str(self.cert), "-inkey", str(self.key)]
            plain = subprocess.run(command, capture_output=True, check=True).stdout
            self.assertEqual(plain, REPORT.encode())
            damaged = bytearray(target.read_bytes())
            damaged[-1] ^= 1
            target.write_bytes(damaged)
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_invalid_recipient_and_mismatch_are_generic_and_create_nothing(self):
        for changes in [{"ENCRYPTED_REPORT_RECIPIENT": ""},
                        {"ENCRYPTED_REPORT_RECIPIENT": CANARY},
                        {"ENCRYPTED_REPORT_RECIPIENT_SHA256": "0" * 64},
                        {"ENCRYPTED_REPORT_RECIPIENT_SHA256": ""},
                        {"ENCRYPTED_REPORT_RECIPIENT": self.cert.read_text() + self.key.read_text()}]:
            with self.subTest(changes=list(changes)), tempfile.TemporaryDirectory() as directory:
                source, target = Path(directory) / "report", Path(directory) / "cipher"
                source.write_text(REPORT)
                result = self.run_cli(source, target, {**self.env, **changes})
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(CANARY, result.stdout + result.stderr)
                self.assertNotIn("PRIVATE KEY", result.stdout + result.stderr)
                self.assertFalse(target.exists())

    def test_invalid_missing_oversize_and_symlink_reports_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / "report", Path(directory) / "cipher"
            for payload in [None, CANARY.encode(), b"\xff", b"x" * (1024 * 1024 + 1)]:
                if payload is not None:
                    source.write_bytes(payload)
                result = self.run_cli(source, target)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(CANARY, result.stdout + result.stderr)
                self.assertFalse(target.exists())
            source.unlink()
            source.symlink_to(self.cert)
            self.assertNotEqual(self.run_cli(source, target).returncode, 0)
            self.assertFalse(target.exists())

    def test_encryption_failure_does_not_publish_partial_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / "report", root / "cipher"
            source.write_text(REPORT)
            fake = root / "openssl"
            fake.write_text("#!/bin/sh\nprintf 'PRIVATE_ENCRYPTION_FAILURE' >&2\nexit 1\n")
            fake.chmod(0o700)
            result = self.run_cli(source, target, {**self.env, "PATH": f"{root}:{os.environ['PATH']}"})
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PRIVATE_ENCRYPTION_FAILURE", result.stdout + result.stderr)
            self.assertFalse(target.exists())

    def test_future_and_expired_certificates_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "index").write_text("")
            (root / "serial").write_text("01\n")
            config = root / "ca.conf"
            config.write_text(f"""[ca]
default_ca = local
[local]
database = {root}/index
serial = {root}/serial
new_certs_dir = {root}
default_md = sha256
policy = policy
unique_subject = no
[policy]
commonName = supplied
""")
            csr = root / "request.pem"
            subprocess.run(["openssl", "req", "-new", "-key", str(self.key),
                            "-subj", "/CN=Synthetic date test/", "-out", str(csr)],
                           check=True, capture_output=True)
            now = datetime.now(timezone.utc)
            for start_days, end_days in [(1, 2), (-2, -1)]:
                with self.subTest(start_days=start_days):
                    cert = root / "dated.pem"
                    subprocess.run(["openssl", "ca", "-batch", "-selfsign", "-notext",
                                    "-config", str(config), "-keyfile", str(self.key),
                                    "-cert", str(self.cert), "-in", str(csr), "-out", str(cert),
                                    "-startdate", (now + timedelta(days=start_days)).strftime("%Y%m%d%H%M%SZ"),
                                    "-enddate", (now + timedelta(days=end_days)).strftime("%Y%m%d%H%M%SZ")],
                                   check=True, capture_output=True)
                    der = subprocess.check_output(["openssl", "x509", "-in", str(cert), "-outform", "DER"])
                    source, target = root / "report", root / "cipher"
                    source.write_text(REPORT)
                    result = self.run_cli(source, target, {**self.env,
                        "ENCRYPTED_REPORT_RECIPIENT": cert.read_text(),
                        "ENCRYPTED_REPORT_RECIPIENT_SHA256": hashlib.sha256(der).hexdigest()})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(target.exists())
                    self.assertNotIn(CANARY, result.stdout + result.stderr)

    def test_actual_publication_sequence_preserves_failure_and_keeps_prose_private(self):
        validation = (ROOT / "scripts/validate.sh").read_text()
        start = validation.index('  if ! "$SCRIPT_DIR/scripts/publish-validation-report.py" \\\n      --report "$candidate_file"')
        end = validation.index('  # Parse results and set outputs', start)
        sequence = validation[start:end]
        for enabled in [False, True, "invalid"]:
            with self.subTest(enabled=enabled), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                candidate, public, outputs = root / "candidate", root / "public", root / "outputs"
                candidate.write_text(REPORT)
                env = {**self.env, "ACTION_PATH": str(ROOT), "VALIDATE_SH_LIBRARY_ONLY": "true",
                       "VALIDATION_REPORT_PATH": str(public), "REPORT_VISIBILITY": "metadata-only",
                       "GITHUB_OUTPUT": str(outputs), "CANDIDATE": str(candidate)}
                if enabled is False:
                    env.pop("ENCRYPTED_REPORT_RECIPIENT")
                    env.pop("ENCRYPTED_REPORT_RECIPIENT_SHA256")
                elif enabled == "invalid":
                    env["ENCRYPTED_REPORT_RECIPIENT_SHA256"] = "0" * 64
                script = ('source "$ACTION_PATH/scripts/validate.sh"\n'
                          'publish_fixture() {\nlocal candidate_file="$CANDIDATE"\n'
                          'local grounding_status=complete\n' + sequence +
                          '\nwrite_outputs failed false 1 complete\n}\npublish_fixture\n')
                result = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
                output = outputs.read_text()
                self.assertNotIn(CANARY, public.read_text() + output + result.stdout + result.stderr)
                self.assertFalse(candidate.exists())
                if enabled == "invalid":
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("validation_status=error", output)
                    self.assertNotIn("encrypted_report_ready=true", output)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("validation_status=failed", output)
                    self.assertIn("critical_issues=1", output)
                self.assertEqual(Path(str(public) + ".cms").exists(), enabled is True)

    def test_upload_and_cleanup_boundary(self):
        action = (ROOT / "action.yml").read_text()
        upload = action.split("    - name: Upload Encrypted Final Report\n", 1)[1].split("    - name:", 1)[0]
        self.assertIn("encrypted_report_ready == 'true'", upload)
        self.assertIn("path: ${{ steps.publication.outputs.report_path }}.cms", upload)
        self.assertIn("retention-days: 1", upload)
        self.assertNotIn("validation-full-output", upload)
        cleanup = action.split("    - name: Cleanup Secrets\n", 1)[1].split("    - name:", 1)[0]
        self.assertIn("if: always()", cleanup)
        self.assertIn('"${REPORT_PATH}.cms"', cleanup)
        self.assertIn("rm -f /tmp/validation-full-output.md", cleanup)
