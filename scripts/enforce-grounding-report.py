#!/usr/bin/env python3
"""Add the action-owned grounding result and fail closed when it is incomplete."""

import argparse
import re
import sys

OUTCOME = "## Validation Outcome"
STATUS_RE = re.compile(r"^- \*\*Status\*\*:\s*(?:PASS|FAIL)(?:\s+[✅❌])?\s*$", re.MULTILINE)
CRITICAL_RE = re.compile(r"^- \*\*Critical Issues\*\*:\s*([0-9]+)\s*$", re.MULTILINE)


def enforce(text, grounding_status, required_count=0, missing_count=0, failed_count=0):
    if grounding_status not in {"complete", "incomplete", "not-required"}:
        raise ValueError("invalid grounding status")
    if text.count(OUTCOME) != 1:
        raise ValueError("report must contain exactly one validation outcome")

    if grounding_status == "complete":
        label = "COMPLETE ✅"
        detail = f"All {required_count} declared required fragment(s) were retrieved and identity/workspace checked."
    elif grounding_status == "not-required":
        label = "NOT REQUIRED"
        detail = "No required fragment IDs were declared; this run is not certified as deterministically grounded."
    else:
        label = "INCOMPLETE ❌"
        detail = (
            "Required or attempted grounding reads were unresolved "
            f"(missing required: {missing_count}; failed attempts: {failed_count})."
        )

    section = f"## Grounding Status\n- **Status**: {label}\n- **Detail**: {detail}\n\n"
    text = text.replace(OUTCOME, section + OUTCOME, 1)
    if grounding_status == "incomplete":
        text, status_changes = STATUS_RE.subn("- **Status**: FAIL ❌", text, count=1)
        match = CRITICAL_RE.search(text)
        if status_changes != 1 or match is None:
            raise ValueError("report outcome fields are missing")
        count = max(1, int(match.group(1)))
        text = text[: match.start()] + f"- **Critical Issues**: {count}" + text[match.end() :]
    return text


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report")
    parser.add_argument("--status", required=True)
    parser.add_argument("--required-count", type=int, default=0)
    parser.add_argument("--missing-count", type=int, default=0)
    parser.add_argument("--failed-count", type=int, default=0)
    args = parser.parse_args(argv)
    try:
        with open(args.report, encoding="utf-8") as handle:
            text = handle.read()
        updated = enforce(text, args.status, args.required_count, args.missing_count, args.failed_count)
        with open(args.report, "w", encoding="utf-8") as handle:
            handle.write(updated)
    except (OSError, ValueError) as exc:
        print(f"Could not enforce grounding status: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
