#!/usr/bin/env python3
"""Opt-in action-owned encrypted attempt capture. No raw diagnostics on stdout."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location(
    "encryption", Path(__file__).with_name("encrypt-validation-report.py"))
ENCRYPTION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENCRYPTION)
MAX_BYTES = 16 * 1024 * 1024


def read_input(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise ValueError("not_regular")
        data = handle.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("too_large")
    return {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
            "base64": base64.b64encode(data).decode("ascii")}


def capture(args):
    if not 1 <= args.attempt <= 100 or not 0 <= args.exit_code <= 255:
        raise ValueError("invalid_attempt")
    bundle = {
        "schema": 1, "attempt": args.attempt, "provider": args.provider,
        "model": args.model, "exit_code": args.exit_code,
        "provenance": {key: os.environ.get(key, "") for key in (
            "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB",
            "GITHUB_SHA", "BASE_BRANCH", "HEAD_BRANCH")},
        "inputs": {name: read_input(getattr(args, name)) for name in ("prompt", "stdout", "stderr")},
    }
    # Deliberately never collect environment dumps or provider credential configs.
    ENCRYPTION.encrypt_payload(json.dumps(bundle, separators=(",", ":")).encode(), args.output,
                               os.environ.get("ENCRYPTED_ATTEMPT_RECIPIENT", ""),
                               os.environ.get("ENCRYPTED_ATTEMPT_RECIPIENT_SHA256", ""))


def main():
    parser = ENCRYPTION.SafeParser()
    for name in ("prompt", "stdout", "stderr", "output", "model"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--provider", choices=("opencode", "gemini"), required=True)
    parser.add_argument("--attempt", type=int, required=True)
    parser.add_argument("--exit-code", type=int, required=True)
    try:
        capture(parser.parse_args())
    except (OSError, ValueError, OverflowError, UnicodeError, subprocess.SubprocessError):
        print("Encrypted attempt capture failed; no plaintext fallback.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
