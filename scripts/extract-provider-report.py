#!/usr/bin/env python3
"""Extract only the final assistant answer from pinned provider JSON output.

OpenCode 1.18.17 emits line-delimited raw events for ``run --format json``;
completed assistant text uses ``{"type":"text","part":{"type":"text","text":...}}``.
Gemini CLI 0.7.0 emits one JSON object for ``--output-format json`` with the
final assistant answer in the top-level ``response`` string. Tool events and
provider metadata are never copied into the report candidate.
"""

import argparse
import json
import sys


def _opencode(text):
    final_text = None
    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"OpenCode output line {line_number} is not JSON") from exc
        if not isinstance(event, dict):
            raise ValueError(f"OpenCode output line {line_number} is not an object")
        if event.get("type") != "text":
            continue
        part = event.get("part")
        if not isinstance(part, dict) or part.get("type") != "text":
            raise ValueError("OpenCode text event has an invalid part")
        value = part.get("text")
        if not isinstance(value, str):
            raise ValueError("OpenCode text event has no text")
        final_text = value
    if final_text is None or not final_text.strip():
        raise ValueError("OpenCode output has no completed assistant text event")
    return final_text.strip()


def _gemini(text):
    try:
        output = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError("Gemini output is not JSON") from exc
    if not isinstance(output, dict):
        raise ValueError("Gemini output is not an object")
    if output.get("error") is not None:
        raise ValueError("Gemini output contains an error")
    response = output.get("response")
    if not isinstance(response, str) or not response.strip():
        raise ValueError("Gemini output has no final response")
    return response.strip()


def extract(provider, text):
    if provider == "opencode":
        return _opencode(text)
    if provider == "gemini":
        return _gemini(text)
    raise ValueError("unsupported provider")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", choices=("opencode", "gemini"), required=True)
    parser.add_argument("input")
    args = parser.parse_args(argv)
    try:
        with open(args.input, encoding="utf-8") as handle:
            result = extract(args.provider, handle.read())
    except (OSError, ValueError) as exc:
        print(f"Could not extract provider response: {exc}", file=sys.stderr)
        return 1
    sys.stdout.write(result + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
