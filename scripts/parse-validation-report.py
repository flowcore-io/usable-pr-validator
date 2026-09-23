#!/usr/bin/env python3
"""Normalize and parse the validator's final Markdown verdict."""

import argparse
import json
import re
import sys

HEADER = "# PR Validation Report"
OUTCOME = "## Validation Outcome"
HEADER_RE = re.compile(r"^# PR Validation Report\s*$", re.MULTILINE)
STATUS_RE = re.compile(r"^- \*\*Status\*\*:\s*(PASS|FAIL)(?:\s+[✅❌])?\s*$", re.MULTILINE)
CRITICAL_RE = re.compile(r"^- \*\*Critical Issues\*\*:\s*([0-9]+)\s*$", re.MULTILINE)
PREAMBLE_RE = re.compile(
    r"^(?:here (?:is|is the|is your)|below is) "
    r"(?:the |your )?(?:requested |final )?(?:pr validation )?report[:.]?$",
    re.IGNORECASE,
)
FENCE_RE = re.compile(r"^```(?:markdown|md)?$", re.IGNORECASE)


def normalize_report(text):
    """Remove only a conservative preamble/fence around one report.

    The provider response is already isolated before this runs. We allow one
    known harmless introductory line and one full Markdown code fence, but no
    arbitrary prose, trailing commentary, or multiple report headers.
    """
    lines = text.lstrip("\ufeff").splitlines()
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        raise ValueError("report is empty")

    if PREAMBLE_RE.fullmatch(lines[0].strip()):
        lines.pop(0)
        while lines and not lines[0].strip():
            lines.pop(0)

    fenced = bool(lines and FENCE_RE.fullmatch(lines[0].strip()))
    if fenced:
        lines.pop(0)
        while lines and not lines[0].strip():
            lines.pop(0)
        while lines and not lines[-1].strip():
            lines.pop()
        if not lines or lines[-1].strip() != "```":
            raise ValueError("report Markdown fence is not closed")
        lines.pop()
        while lines and not lines[-1].strip():
            lines.pop()

    normalized = "\n".join(lines).strip()
    if len(HEADER_RE.findall(normalized)) != 1:
        raise ValueError("report must contain exactly one required header")
    if not normalized.startswith(HEADER):
        raise ValueError("report must start with the required header")
    return normalized


def parse_report(text):
    text = normalize_report(text)
    if text.count(OUTCOME) != 1:
        raise ValueError("report must contain exactly one validation outcome")
    outcome = text.split(OUTCOME, 1)[1]
    next_section = re.search(r"^## ", outcome, re.MULTILINE)
    if next_section:
        outcome = outcome[: next_section.start()]
    statuses = STATUS_RE.findall(outcome)
    critical_counts = CRITICAL_RE.findall(outcome)
    if len(statuses) != 1 or len(critical_counts) != 1:
        raise ValueError("validation outcome must contain one status and one critical count")
    status = statuses[0]
    critical_issues = int(critical_counts[0])
    if status == "PASS" and critical_issues != 0:
        raise ValueError("PASS cannot contain critical issues")
    # FAIL can reflect important findings or incomplete assessment without
    # inventing a critical violation. Preserve the failed verdict verbatim.
    return {
        "status": "passed" if status == "PASS" else "failed",
        "passed": status == "PASS",
        "critical_issues": critical_issues,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--normalize", action="store_true", help="print normalized report Markdown")
    parser.add_argument("report")
    args = parser.parse_args(argv)
    try:
        with open(args.report, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        print(f"Invalid validation report: {exc}", file=sys.stderr)
        return 1
    if args.normalize:
        try:
            normalized = normalize_report(text)
        except ValueError as exc:
            print(f"Invalid validation report: {exc}", file=sys.stderr)
            return 1
        sys.stdout.write(normalized + "\n")
        return 0

    try:
        result = parse_report(text)
    except ValueError as exc:
        print(f"Invalid validation report: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
