#!/usr/bin/env python3
"""Validate and prefetch the action's declared required Usable fragments."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import uuid

SCRIPT = Path(__file__).with_name("read-usable-fragment.py")
spec = importlib.util.spec_from_file_location("usable_fragment_reader", SCRIPT)
assert spec is not None and spec.loader is not None
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


def parse_ids(value):
    if not value.strip():
        return []
    values = [item.lower() for item in re.split(r"[\s,]+", value.strip()) if item]
    if any(not reader.UUID_PATTERN.fullmatch(item) for item in values):
        raise ValueError("required-fragment-ids must contain only UUIDs separated by commas or whitespace")
    return list(dict.fromkeys(values))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ids", default=os.environ.get("REQUIRED_FRAGMENT_IDS", ""))
    parser.add_argument("--workspace-id", default=os.environ.get("WORKSPACE_ID", ""))
    parser.add_argument("--required-file", default="/tmp/usable-required-fragments.txt")
    parser.add_argument("--ledger", default="/tmp/usable-grounding-ledger.jsonl")
    parser.add_argument("--output", default="/tmp/usable-required-grounding.md")
    args = parser.parse_args(argv)

    try:
        fragment_ids = parse_ids(args.ids)
        reader._require_uuid(args.workspace_id, "workspace_id")
    except ValueError as exc:
        print(f"Required fragment configuration is invalid: {exc}", file=sys.stderr)
        return 2

    Path(args.required_file).write_text("".join(fragment_id + "\n" for fragment_id in fragment_ids), encoding="utf-8")
    Path(args.ledger).write_text("", encoding="utf-8")
    os.chmod(args.required_file, 0o600)
    os.chmod(args.ledger, 0o600)

    sections = []
    token = reader.configured_token()
    for fragment_id in fragment_ids:
        attempt_id = str(uuid.uuid4())
        reader.append_ledger(args.ledger, fragment_id, "pending", attempt_id=attempt_id)
        try:
            fragment = reader.read_fragment(fragment_id, token, args.workspace_id)
        except (ValueError, reader.FragmentReadError) as exc:
            code = exc.code if isinstance(exc, reader.FragmentReadError) else "validation_error"
            reader.append_ledger(args.ledger, fragment_id, "failed", code, attempt_id=attempt_id)
            print(f"Required Usable fragment could not be retrieved: {fragment_id} ({code})", file=sys.stderr)
            return 1
        reader.append_ledger(args.ledger, fragment_id, "success", attempt_id=attempt_id)
        sections.append(
            "\n".join(
                [
                    f"## {fragment['title']}",
                    f"- Fragment ID: `{fragment['id']}`",
                    f"- Workspace ID: `{fragment['workspaceId']}`",
                    f"- Updated: `{fragment['updatedAt'] or 'unknown'}`",
                    "",
                    fragment["content"],
                ]
            )
        )

    heading = "# Deterministically Prefetched Usable Grounding\n"
    if sections:
        body = heading + "\n" + "\n\n---\n\n".join(sections) + "\n"
    else:
        body = heading + "\nNo required fragment IDs were declared. This run is not certified as deterministically grounded.\n"
    Path(args.output).write_text(body, encoding="utf-8")
    os.chmod(args.output, 0o600)
    print(json.dumps({"required_count": len(fragment_ids), "prefetch": "complete"}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
