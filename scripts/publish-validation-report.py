#!/usr/bin/env python3
"""The only boundary from private assistant prose to a public report.

Metadata-only is intentionally a projection, not a secret-redaction heuristic.
Full Markdown publication requires an exact, trusted caller opt-in.
"""

import argparse
import importlib.util
import os
from pathlib import Path
import stat
import sys
import tempfile

SPEC = importlib.util.spec_from_file_location(
    "validation_parser", Path(__file__).with_name("parse-validation-report.py")
)
PARSER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PARSER)
MAX_REPORT_BYTES = 1024 * 1024
GROUNDING_LABELS = {
    "complete": "COMPLETE",
    "incomplete": "INCOMPLETE",
    "not-required": "NOT REQUIRED",
}
VISIBILITIES = {"metadata-only", "full"}


def render(text, grounding_status, visibility="metadata-only"):
    if visibility not in VISIBILITIES or grounding_status not in GROUNDING_LABELS:
        raise ValueError("publication_policy_invalid")
    if len(text.encode("utf-8")) > MAX_REPORT_BYTES:
        raise ValueError("report_too_large")
    result = PARSER.parse_report(text)
    if grounding_status == "incomplete" and result["passed"]:
        raise ValueError("grounding_inconsistent")
    if visibility == "full":
        return PARSER.normalize_report(text) + "\n"
    verdict = "PASS" if result["passed"] else "FAIL"
    return (
        "# PR Validation Report\n\n"
        "## Summary\n"
        "Only action-generated validation metadata is published. Assistant prose, "
        "source excerpts, links, and retrieved standards are withheld.\n\n"
        "## Grounding Status\n"
        f"- **Status**: {GROUNDING_LABELS[grounding_status]}\n\n"
        "## Validation Outcome\n"
        f"- **Status**: {verdict}\n"
        f"- **Critical Issues**: {result['critical_issues']}\n"
    )


def error_report():
    # No caller/model exception text is accepted as public error prose.
    return (
        "# PR Validation Report\n\n## Summary\n"
        "Validation infrastructure failure: no validated assistant report is available.\n\n"
        "## Validation Outcome\n- **Status**: FAIL\n- **Critical Issues**: 1\n"
    )


def read_private(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise ValueError("report_not_regular")
        content = handle.read(MAX_REPORT_BYTES + 1)
    if len(content) > MAX_REPORT_BYTES:
        raise ValueError("report_too_large")
    return content.decode("utf-8")


def publish(target, content):
    target = Path(target)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=target.parent,
                                         prefix=".report-", delete=False) as handle:
            temporary = Path(handle.name)
            os.fchmod(handle.fileno(), 0o600)
            handle.write(content)
        os.replace(temporary, target)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, "Report publication rejected: invalid arguments.\n")


def main(argv=None):
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("--report")
    parser.add_argument("--output", required=True)
    parser.add_argument("--visibility", default="metadata-only")
    parser.add_argument("--grounding-status", default="incomplete")
    parser.add_argument("--error", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.visibility not in VISIBILITIES or args.grounding_status not in GROUNDING_LABELS:
            raise ValueError("invalid_policy")
        if args.error:
            content = render(error_report(), args.grounding_status, "metadata-only")
            # Keep the generic failure explanation, never a supplied summary.
            content = content.replace("Only action-generated validation metadata is published.",
                                      "Validation infrastructure failure. Only action-generated validation metadata is published.")
        elif args.report:
            content = render(read_private(args.report), args.grounding_status, args.visibility)
        else:
            raise ValueError("missing_report")
        publish(args.output, content)
    except (OSError, ValueError, UnicodeError):
        print("Report publication rejected: invalid report or policy.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
