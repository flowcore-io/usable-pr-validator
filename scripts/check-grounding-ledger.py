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
        attempt_id = record.get("attempt_id") if isinstance(record, dict) else None
        if not isinstance(fragment_id, str) or status not in {"pending", "success", "failed"}:
            raise ValueError("grounding ledger contains an invalid record")
        valid_identity = UUID_PATTERN.fullmatch(fragment_id) or (status == "failed" and fragment_id == "invalid-input")
        if not valid_identity:
            raise ValueError("grounding ledger contains an invalid record")
        if attempt_id is not None and (not isinstance(attempt_id, str) or not UUID_PATTERN.fullmatch(attempt_id)):
            raise ValueError("grounding ledger contains an invalid attempt ID")
        if status == "pending" and attempt_id is None:
            raise ValueError("pending grounding record has no attempt ID")
        records.append({"fragment_id": fragment_id.lower(), "status": status, "attempt_id": attempt_id})
    return records


def evaluate(required_path, ledger_path):
    required = _required(required_path)
    records = _records(ledger_path)
    successful = {record["fragment_id"] for record in records if record["status"] == "success"}
    completed_attempts = {
        (record["attempt_id"], record["fragment_id"])
        for record in records
        if record["attempt_id"] is not None and record["status"] in {"success", "failed"}
    }
    unresolved = {
        record["fragment_id"]
        for record in records
        if record["status"] == "pending"
        and (record["attempt_id"], record["fragment_id"]) not in completed_attempts
    }
    failed = sorted(
        {record["fragment_id"] for record in records if record["status"] == "failed"} | unresolved
    )
    missing = sorted(set(required) - successful)
    if missing or failed:
        status = "incomplete"
    elif not required:
        status = "not-required"
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
