#!/usr/bin/env python3
"""Emit content-free provider failure metadata from private CLI output."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ALLOWED_ERROR_NAMES = {
    "APIError",
    "ContextOverflowError",
    "MessageAbortedError",
    "MessageOutputLengthError",
    "ProviderAuthError",
    "ProviderInitError",
    "ProviderModelNotFoundError",
    "StructuredOutputError",
    "UnknownError",
}

ALLOWED_ERROR_CODES = {
    "authentication_error",
    "context_length_exceeded",
    "insufficient_quota",
    "invalid_api_key",
    "invalid_prompt",
    "model_not_found",
    "rate_limit_exceeded",
    "server_error",
    "server_is_overloaded",
    "unauthorized",
    "usage_not_included",
}


def _error_object(event: Any) -> dict[str, Any] | None:
    if not isinstance(event, dict) or event.get("type") != "error":
        return None
    error = event.get("error")
    return error if isinstance(error, dict) else None


def _direct_code(error: dict[str, Any], data: dict[str, Any]) -> str | None:
    for value in (error.get("code"), data.get("code")):
        if not isinstance(value, str):
            continue
        return value if value in ALLOWED_ERROR_CODES else "unrecognized"
    return None


def summarize(provider: str, stdout_text: str, stderr_text: str) -> dict[str, Any]:
    names: set[str] = set()
    statuses: set[int] = set()
    codes: set[str] = set()
    retryable_values: list[bool] = []
    malformed_lines = 0
    error_events = 0

    for line in stdout_text.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            malformed_lines += 1
            continue

        error = _error_object(event)
        if error is None:
            continue
        error_events += 1

        name = error.get("name")
        if isinstance(name, str):
            names.add(name if name in ALLOWED_ERROR_NAMES else "unrecognized")

        data = error.get("data")
        if not isinstance(data, dict):
            data = {}

        status = data.get("statusCode")
        if isinstance(status, int) and not isinstance(status, bool) and 100 <= status <= 599:
            statuses.add(status)

        retryable = data.get("isRetryable")
        if isinstance(retryable, bool):
            retryable_values.append(retryable)

        code = _direct_code(error, data)
        if code is not None:
            codes.add(code)

    if any(retryable_values):
        retryable: bool | None = True
    elif retryable_values:
        retryable = False
    else:
        retryable = None

    missing_fields = []
    if not names:
        missing_fields.append("name")
    if not codes:
        missing_fields.append("code")
    if not retryable_values:
        missing_fields.append("retryable")
    if not statuses:
        missing_fields.append("status_code")

    safe_provider = provider if provider in {"opencode", "gemini"} else "unknown"
    return {
        "provider": safe_provider,
        "structured_error_events": error_events,
        "malformed_output_lines": malformed_lines,
        "error_names": sorted(names),
        "status_codes": sorted(statuses),
        "error_codes": sorted(codes),
        "retryable": retryable,
        "missing_fields": sorted(missing_fields),
        "stdout_present": bool(stdout_text),
        "stderr_present": bool(stderr_text),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True)
    parser.add_argument("--stdout-file", required=True)
    parser.add_argument("--stderr-file", required=True)
    args = parser.parse_args(argv)

    stdout_text = Path(args.stdout_file).read_text(encoding="utf-8", errors="replace")
    stderr_text = Path(args.stderr_file).read_text(encoding="utf-8", errors="replace")
    print(json.dumps(summarize(args.provider, stdout_text, stderr_text), sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
