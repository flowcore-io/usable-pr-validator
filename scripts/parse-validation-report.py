#!/usr/bin/env python3
"""Parse the validator's exact final Markdown verdict into JSON."""

import argparse
import json
import re
import sys

HEADER = "# PR Validation Report"
OUTCOME = "## Validation Outcome"
STATUS_RE = re.compile(r"^- \*\*Status\*\*:\s*(PASS|FAIL)(?:\s+[✅❌])?\s*$", re.MULTILINE)
CRITICAL_RE = re.compile(r"^- \*\*Critical Issues\*\*:\s*([0-9]+)\s*$", re.MULTILINE)


def parse_report(text):
    if not text.startswith(HEADER):
        raise ValueError("report must start with the required header")
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
    if status == "FAIL" and critical_issues == 0:
        raise ValueError("FAIL must contain at least one critical issue")
    return {
        "status": "passed" if status == "PASS" else "failed",
        "passed": status == "PASS",
        "critical_issues": critical_issues,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report")
    args = parser.parse_args(argv)
    try:
        with open(args.report, encoding="utf-8") as handle:
            result = parse_report(handle.read())
    except (OSError, ValueError) as exc:
        print(f"Invalid validation report: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
