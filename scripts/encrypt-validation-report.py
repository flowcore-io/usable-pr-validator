#!/usr/bin/env python3
"""Opt-in encrypted final report; no plaintext output or transcript fallback."""

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SPEC = importlib.util.spec_from_file_location(
    "publication", Path(__file__).with_name("publish-validation-report.py")
)
PUBLICATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLICATION)


def openssl(*args, data=None):
    return subprocess.run(
        ["openssl", *args], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, check=True, timeout=20,
    ).stdout


def encrypt(report, output):
    pem = os.environ.get("ENCRYPTED_REPORT_RECIPIENT", "")
    fingerprint = os.environ.get("ENCRYPTED_REPORT_RECIPIENT_SHA256", "")
    if not re.fullmatch(r"[a-fA-F0-9]{64}", fingerprint):
        raise ValueError("invalid_fingerprint")
    if len(pem) > 16384 or not re.fullmatch(
        r"\s*-----BEGIN CERTIFICATE-----\s+[A-Za-z0-9+/=\r\n]+"
        r"-----END CERTIFICATE-----\s*", pem
    ):
        raise ValueError("invalid_certificate")
    text = PUBLICATION.read_private(report)
    PUBLICATION.PARSER.parse_report(text)
    if not openssl("version").startswith(b"OpenSSL 3."):
        raise ValueError("openssl_3_required")
    with tempfile.TemporaryDirectory(prefix="validator-recipient-") as directory:
        certificate = Path(directory) / "recipient.pem"
        certificate.write_text(pem)
        certificate.chmod(0o600)
        der = openssl("x509", "-in", str(certificate), "-outform", "DER")
        if hashlib.sha256(der).hexdigest() != fingerprint.lower():
            raise ValueError("recipient_mismatch")
        openssl("x509", "-in", str(certificate), "-checkend", "0", "-noout")
        start = openssl("x509", "-in", str(certificate), "-startdate", "-noout")
        not_before = datetime.strptime(
            start.decode("ascii").strip().removeprefix("notBefore="),
            "%b %d %H:%M:%S %Y GMT",
        ).replace(tzinfo=timezone.utc)
        if not_before > datetime.now(timezone.utc):
            raise ValueError("recipient_not_yet_valid")
        public_key = openssl("x509", "-in", str(certificate), "-pubkey", "-noout")
        description = openssl("pkey", "-pubin", "-text", "-noout", data=public_key)
        bits = re.search(rb"Public-Key: \((\d+) bit\)", description)
        if not bits or not 3072 <= int(bits[1]) <= 8192:
            raise ValueError("invalid_recipient_key")
        # AuthEnvelopedData: AES-GCM integrity plus RSA-OAEP/SHA256 key wrapping.
        # Non-RSA recipients fail the RSA key options; no weaker fallback exists.
        ciphertext = openssl(
            "cms", "-encrypt", "-binary", "-aes-256-gcm", "-outform", "DER",
            "-recip", str(certificate), "-keyopt", "rsa_padding_mode:oaep",
            "-keyopt", "rsa_oaep_md:sha256", "-keyopt", "rsa_mgf1_md:sha256",
            data=text.encode("utf-8"),
        )
    if not ciphertext:
        raise ValueError("empty_ciphertext")
    target = Path(output)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as handle:
            temporary = Path(handle.name)
            os.fchmod(handle.fileno(), 0o600)
            handle.write(ciphertext)
        os.replace(temporary, target)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


class SafeParser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, "Encrypted report rejected: invalid arguments.\n")


def main():
    parser = SafeParser()
    parser.add_argument("--report", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        encrypt(args.report, args.output)
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError):
        print("Encrypted report rejected: invalid report, recipient or encryption failure.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
