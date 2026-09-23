#!/usr/bin/env python3
"""Evaluate deterministic Usable fragment reads from the per-run ledger."""

import argparse
import json
import re
import sys

UUID_PATTERN = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"
)


def _required(path):
    try:
        with open(path, encoding="utf-8") as handle:
            values = [line.strip().lower() for line in handle if line.strip()]
    except FileNotFoundError:
        return []
    if any(not UUID_PATTERN.fullmatch(value) for value in values):
        raise ValueError("required fragment file contains a non-UUID")
    return list(dict.fromkeys(values))


def _records(path):
    try:
        with open(path, encoding="utf-8") as handle:
            lines = list(handle)
    except FileNotFoundError:
        return []
    records = []
    for line in lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError("grounding ledger contains malformed JSON") from exc
        fragment_id = record.get("fragment_id") if isinstance(record, dict) else None
        status = record.get("status") if isinstance(record, dict) else None
        if not isinstance(fragment_id, str) or status not in {"success", "failed"}:
            raise ValueError("grounding ledger contains an invalid record")
        valid_identity = UUID_PATTERN.fullmatch(fragment_id) or (status == "failed" and fragment_id == "invalid-input")
        if not valid_identity:
            raise ValueError("grounding ledger contains an invalid record")
        records.append({"fragment_id": fragment_id.lower(), "status": status})
    return records


def evaluate(required_path, ledger_path):
    required = _required(required_path)
    records = _records(ledger_path)
    successful = {record["fragment_id"] for record in records if record["status"] == "success"}
    failed = sorted({record["fragment_id"] for record in records if record["status"] == "failed"})
    missing = sorted(set(required) - successful)
    if not required and not records:
        status = "not-required"
    elif missing or failed:
        status = "incomplete"
    else:
        status = "complete"
    return {
        "status": status,
        "required_count": len(required),
        "successful_count": len(successful),
        "missing_required": missing,
        "failed_attempts": failed,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--required", required=True)
    parser.add_argument("--ledger", required=True)
    args = parser.parse_args(argv)
    try:
        result = evaluate(args.required, args.ledger)
    except (OSError, ValueError) as exc:
        print(f"Invalid grounding ledger: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result["status"] != "incomplete" else 1


if __name__ == "__main__":
    sys.exit(main())
