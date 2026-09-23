#!/usr/bin/env python3
"""Read one complete Usable fragment through a fixed, read-only REST endpoint."""

import http.client
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.request
import uuid

API_ORIGIN = "https://usable.dev"
API_PATH_PREFIX = "/api/memory-fragments/"
REQUEST_TIMEOUT_SECONDS = 20
MAX_RESPONSE_BYTES = 5 * 1024 * 1024
DEFAULT_MAX_RETRIES = 2
TRANSIENT_HTTP_STATUSES = {429, 500, 502, 503, 504}
UUID_PATTERN = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"
)


class FragmentReadError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _require_uuid(value, field):
    if not isinstance(value, str) or not UUID_PATTERN.fullmatch(value):
        raise ValueError(f"{field} must be a UUID")


def _decode_response(response):
    content_length = response.headers.get("Content-Length")
    if content_length:
        try:
            if int(content_length) > MAX_RESPONSE_BYTES:
                raise FragmentReadError("response_too_large")
        except ValueError as exc:
            raise FragmentReadError("invalid_content_length") from exc
    payload = response.read(MAX_RESPONSE_BYTES + 1)
    if len(payload) > MAX_RESPONSE_BYTES:
        raise FragmentReadError("response_too_large")
    try:
        return json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise FragmentReadError("malformed_json") from exc


def _validate_fragment(data, fragment_id, workspace_id):
    if not isinstance(data, dict) or data.get("success") is not True:
        raise ValueError("unexpected response envelope")
    fragment = data.get("fragment")
    if not isinstance(fragment, dict):
        raise ValueError("unexpected fragment envelope")
    identity = fragment.get("id")
    if not isinstance(identity, str) or identity.lower() != fragment_id.lower():
        raise ValueError("unexpected fragment identity")
    if fragment.get("workspaceId") != workspace_id:
        raise ValueError("unexpected fragment workspace")
    content = fragment.get("content")
    if not isinstance(content, str):
        raise ValueError("fragment has no text content")
    if fragment.get("isPartial") is True or fragment.get("truncated") is True:
        raise ValueError("fragment content is partial")
    return {
        "id": identity,
        "title": fragment.get("title") if isinstance(fragment.get("title"), str) else "Untitled fragment",
        "workspaceId": workspace_id,
        "updatedAt": fragment.get("updatedAt") if isinstance(fragment.get("updatedAt"), str) else None,
        "content": content,
    }


def read_fragment(
    fragment_id,
    token,
    workspace_id,
    opener=None,
    sleeper=time.sleep,
    max_retries=DEFAULT_MAX_RETRIES,
):
    _require_uuid(fragment_id, "fragment_id")
    _require_uuid(workspace_id, "workspace_id")
    if not token:
        raise ValueError("API token is unavailable")
    if not isinstance(max_retries, int) or max_retries < 0 or max_retries > 5:
        raise ValueError("max_retries must be between 0 and 5")

    url = API_ORIGIN + API_PATH_PREFIX + fragment_id
    request = urllib.request.Request(
        url,
        headers={"Authorization": "Bearer " + token, "Accept": "application/json"},
        method="GET",
    )
    opener = opener or urllib.request.build_opener(NoRedirect())

    for attempt in range(max_retries + 1):
        try:
            with opener.open(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                final_url = response.geturl() if hasattr(response, "geturl") else url
                if final_url != url:
                    raise FragmentReadError("redirect_refused")
                return _validate_fragment(_decode_response(response), fragment_id, workspace_id)
        except urllib.error.HTTPError as exc:
            if 300 <= exc.code < 400:
                raise FragmentReadError("redirect_refused") from exc
            if exc.code not in TRANSIENT_HTTP_STATUSES or attempt >= max_retries:
                raise FragmentReadError(f"http_{exc.code}") from exc
        except http.client.HTTPException as exc:
            if attempt >= max_retries:
                raise FragmentReadError("protocol_error") from exc
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as exc:
            if attempt >= max_retries:
                raise FragmentReadError("network_error") from exc
        if attempt < max_retries:
            sleeper(2**attempt)
    raise FragmentReadError("retry_exhausted")


def append_ledger(path, fragment_id, status, error=None, attempt_id=None):
    if not path:
        return
    safe_fragment_id = fragment_id.lower() if isinstance(fragment_id, str) and UUID_PATTERN.fullmatch(fragment_id) else "invalid-input"
    record = {"fragment_id": safe_fragment_id, "status": status}
    if attempt_id:
        record["attempt_id"] = attempt_id
    if error:
        record["error"] = error
    encoded = (json.dumps(record, separators=(",", ":")) + "\n").encode("utf-8")
    descriptor = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(descriptor, encoded)
    finally:
        os.close(descriptor)


def configured_token():
    secret_name = os.environ.get("MCP_SECRET_NAME", "USABLE_API_TOKEN")
    return os.environ.get(secret_name, "")


def main(argv=None):
    arguments = list(sys.argv[1:] if argv is None else argv)
    ledger = os.environ.get("USABLE_GROUNDING_LEDGER", "/tmp/usable-grounding-ledger.jsonl")
    if len(arguments) != 1:
        append_ledger(ledger, "invalid-input", "failed", "invalid_invocation")
        print("Usage: read-usable-fragment.py FRAGMENT_UUID", file=sys.stderr)
        return 2

    fragment_id = arguments[0]
    workspace_id = os.environ.get("WORKSPACE_ID", "")
    attempt_id = None

    try:
        _require_uuid(fragment_id, "fragment_id")
        attempt_id = str(uuid.uuid4())
        append_ledger(ledger, fragment_id, "pending", attempt_id=attempt_id)
    except ValueError:
        pass

    try:
        result = read_fragment(
            fragment_id,
            configured_token(),
            workspace_id,
            max_retries=DEFAULT_MAX_RETRIES,
        )
    except (ValueError, FragmentReadError) as exc:
        code = exc.code if isinstance(exc, FragmentReadError) else "validation_error"
        append_ledger(ledger, fragment_id, "failed", code, attempt_id=attempt_id)
        print(f"Usable fragment read failed ({code})", file=sys.stderr)
        return 1
    except OSError:
        append_ledger(ledger, fragment_id, "failed", "local_io_error", attempt_id=attempt_id)
        print("Usable fragment read failed (local_io_error)", file=sys.stderr)
        return 1

    rendered = json.dumps(result, ensure_ascii=False)
    try:
        sys.stdout.write(rendered + "\n")
        sys.stdout.flush()
    except OSError:
        append_ledger(ledger, fragment_id, "failed", "local_io_error", attempt_id=attempt_id)
        print("Usable fragment read failed (local_io_error)", file=sys.stderr)
        return 1

    append_ledger(ledger, fragment_id, "success", attempt_id=attempt_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
