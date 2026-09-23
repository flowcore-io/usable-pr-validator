#!/usr/bin/env python3
"""Extract only the completed final assistant answer from provider JSON.

OpenCode 1.18.17 emits line-delimited events for ``run --format json``. A
completed model step is bounded by ``step_start`` and ``step_finish`` events;
all parts carry a ``messageID``. The final answer can contain multiple completed
text parts, so this extractor joins only text parts from the terminal completed
step. It never joins earlier assistant steps or tool activity.

Gemini CLI 0.7.0 emits one JSON object for ``--output-format json`` with the
final assistant answer in the top-level ``response`` string. Tool events,
provider metadata, and private response bodies are never copied into diagnostics.
"""

import argparse
from collections import Counter
import json
import re
import sys

HEADER_RE = re.compile(r"(?m)^# PR Validation Report\s*$")
KNOWN_OPENCODE_EVENTS = {"tool_use", "step_start", "step_finish", "text", "reasoning", "error"}


def _safe_event_type(value):
    return value if isinstance(value, str) and value in KNOWN_OPENCODE_EVENTS else "unknown"


class ExtractionError(ValueError):
    def __init__(self, code, message, diagnostics=None):
        super().__init__(message)
        self.code = code
        self.diagnostics = diagnostics or {}


def _response_metadata(provider, response):
    stripped = response.lstrip("\ufeff\r\n\t ")
    header_count = len(HEADER_RE.findall(response))
    starts_with_header = stripped.startswith("# PR Validation Report")
    return {
        "provider": provider,
        "header_count": header_count,
        "starts_with_header": starts_with_header,
        "wrapping": "none" if starts_with_header else ("present" if header_count == 1 else "unknown"),
    }


def _opencode(text):
    events = []
    counts = Counter()
    message_ids = set()
    diagnostics = {
        "provider": "opencode",
        "event_count": 0,
        "event_types": {},
        "message_count": 0,
        "text_part_count": 0,
        "selected_text_parts": 0,
        "terminal_event": None,
    }

    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            diagnostics["error_code"] = "invalid_json_line"
            raise ExtractionError(
                "invalid_json_line",
                f"OpenCode output line {line_number} is not JSON",
                diagnostics,
            ) from exc
        if not isinstance(event, dict):
            diagnostics["error_code"] = "invalid_event"
            raise ExtractionError(
                "invalid_event",
                f"OpenCode output line {line_number} is not an object",
                diagnostics,
            )

        event_type = event.get("type")
        safe_type = _safe_event_type(event_type)
        counts[safe_type] += 1
        part = event.get("part")
        if isinstance(part, dict) and isinstance(part.get("messageID"), str):
            message_ids.add(part["messageID"])
        events.append(event)

    diagnostics.update({
        "event_count": len(events),
        "event_types": dict(sorted(counts.items())),
        "message_count": len(message_ids),
        "text_part_count": counts.get("text", 0),
        "terminal_event": _safe_event_type(events[-1].get("type")) if events else None,
    })

    if not events:
        diagnostics["error_code"] = "empty_output"
        raise ExtractionError("empty_output", "OpenCode output has no events", diagnostics)

    if counts.get("error", 0):
        diagnostics["error_code"] = "provider_error_event"
        raise ExtractionError(
            "provider_error_event",
            "OpenCode output contains an error event",
            diagnostics,
        )

    terminal = events[-1]
    if terminal.get("type") != "step_finish":
        diagnostics["error_code"] = "incomplete_terminal_event"
        raise ExtractionError(
            "incomplete_terminal_event",
            "OpenCode output did not end with a completed step",
            diagnostics,
        )

    terminal_part = terminal.get("part")
    if not isinstance(terminal_part, dict) or terminal_part.get("type") != "step-finish":
        diagnostics["error_code"] = "invalid_terminal_part"
        raise ExtractionError(
            "invalid_terminal_part",
            "OpenCode terminal step has an invalid part",
            diagnostics,
        )
    message_id = terminal_part.get("messageID")
    if not isinstance(message_id, str) or not message_id:
        diagnostics["error_code"] = "missing_terminal_message_id"
        raise ExtractionError(
            "missing_terminal_message_id",
            "OpenCode terminal step has no message ID",
            diagnostics,
        )

    start_index = None
    for index in range(len(events) - 2, -1, -1):
        event = events[index]
        part = event.get("part")
        if (
            event.get("type") == "step_start"
            and isinstance(part, dict)
            and part.get("type") == "step-start"
            and part.get("messageID") == message_id
        ):
            start_index = index
            break
    if start_index is None:
        diagnostics["error_code"] = "missing_terminal_step_start"
        raise ExtractionError(
            "missing_terminal_step_start",
            "OpenCode terminal step has no matching start event",
            diagnostics,
        )

    final_parts = []
    for event in events[start_index + 1 : -1]:
        event_type = event.get("type")
        part = event.get("part")
        if event_type == "tool_use":
            diagnostics["error_code"] = "terminal_step_has_tool"
            raise ExtractionError(
                "terminal_step_has_tool",
                "OpenCode terminal step ended with tool activity instead of a final answer",
                diagnostics,
            )
        if event_type != "text":
            continue
        if not isinstance(part, dict) or part.get("type") != "text":
            diagnostics["error_code"] = "invalid_text_part"
            raise ExtractionError(
                "invalid_text_part",
                "OpenCode text event has an invalid part",
                diagnostics,
            )
        if part.get("messageID") != message_id:
            continue
        value = part.get("text")
        time = part.get("time")
        if not isinstance(value, str) or not isinstance(time, dict) or not time.get("end"):
            diagnostics["error_code"] = "incomplete_text_part"
            raise ExtractionError(
                "incomplete_text_part",
                "OpenCode terminal text part is incomplete",
                diagnostics,
            )
        if value.strip():
            final_parts.append(value.strip())

    diagnostics["selected_text_parts"] = len(final_parts)
    if not final_parts:
        diagnostics["error_code"] = "no_terminal_text"
        raise ExtractionError(
            "no_terminal_text",
            "OpenCode terminal step has no completed assistant text",
            diagnostics,
        )

    response = "\n\n".join(final_parts).strip()
    diagnostics.update(_response_metadata("opencode", response))
    return response, diagnostics


def _gemini(text):
    diagnostics = {
        "provider": "gemini",
        "json_object": False,
        "has_response": False,
        "has_error": False,
    }
    try:
        output = json.loads(text)
    except json.JSONDecodeError as exc:
        diagnostics["error_code"] = "invalid_json"
        raise ExtractionError("invalid_json", "Gemini output is not JSON", diagnostics) from exc
    if not isinstance(output, dict):
        diagnostics["error_code"] = "invalid_object"
        raise ExtractionError("invalid_object", "Gemini output is not an object", diagnostics)
    diagnostics["json_object"] = True
    diagnostics["has_error"] = output.get("error") is not None
    if diagnostics["has_error"]:
        diagnostics["error_code"] = "provider_error"
        raise ExtractionError("provider_error", "Gemini output contains an error", diagnostics)
    response = output.get("response")
    diagnostics["has_response"] = isinstance(response, str) and bool(response.strip())
    if not isinstance(response, str) or not response.strip():
        diagnostics["error_code"] = "missing_response"
        raise ExtractionError("missing_response", "Gemini output has no final response", diagnostics)
    response = response.strip()
    diagnostics.update(_response_metadata("gemini", response))
    diagnostics["selected_text_parts"] = 1
    return response, diagnostics


def extract_with_diagnostics(provider, text):
    if provider == "opencode":
        return _opencode(text)
    if provider == "gemini":
        return _gemini(text)
    raise ExtractionError("unsupported_provider", "unsupported provider", {"provider": provider})


def extract(provider, text):
    response, _ = extract_with_diagnostics(provider, text)
    return response


def _log_diagnostics(diagnostics):
    safe = dict(diagnostics)
    print(
        "Provider report diagnostics: " + json.dumps(safe, sort_keys=True, separators=(",", ":")),
        file=sys.stderr,
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", choices=("opencode", "gemini"), required=True)
    parser.add_argument("input")
    args = parser.parse_args(argv)
    try:
        with open(args.input, encoding="utf-8") as handle:
            result, diagnostics = extract_with_diagnostics(args.provider, handle.read())
    except OSError as exc:
        _log_diagnostics({"provider": args.provider, "error_code": "input_read_failed"})
        print(f"Could not extract provider response: {exc}", file=sys.stderr)
        return 1
    except ExtractionError as exc:
        diagnostics = dict(exc.diagnostics)
        diagnostics["error_code"] = exc.code
        _log_diagnostics(diagnostics)
        print(f"Could not extract provider response: {exc}", file=sys.stderr)
        return 1
    _log_diagnostics(diagnostics)
    sys.stdout.write(result + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
