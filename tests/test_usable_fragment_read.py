import importlib.util
import http.server
import io
import json
import os
from pathlib import Path
import socket
import threading
import tempfile
from contextlib import redirect_stderr
from unittest import mock
import unittest
import urllib.error

SCRIPT = Path(__file__).parents[1] / "scripts" / "read-usable-fragment.py"
spec = importlib.util.spec_from_file_location("reader", SCRIPT)
assert spec is not None and spec.loader is not None
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
LEDGER_SCRIPT = Path(__file__).parents[1] / "scripts" / "check-grounding-ledger.py"
ledger_spec = importlib.util.spec_from_file_location("grounding_ledger", LEDGER_SCRIPT)
assert ledger_spec is not None and ledger_spec.loader is not None
grounding_ledger = importlib.util.module_from_spec(ledger_spec)
ledger_spec.loader.exec_module(grounding_ledger)

FRAGMENT_ID = "a03af556-b85c-4073-8383-08ea7b2b3b8d"
WORKSPACE_ID = "f3c9feef-b8e6-4a23-bda0-0d90cd5162d1"


class FakeResponse(io.BytesIO):
    def __init__(self, payload, headers=None, status=200):
        super().__init__(payload)
        self.headers = headers or {}
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class FakeOpener:
    def __init__(self, outcomes):
        self.outcomes = list(outcomes)
        self.calls = []

    def open(self, request, timeout):
        self.calls.append((request, timeout))
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, BaseException):
            raise outcome
        return outcome


class FlushFailure(io.StringIO):
    def flush(self):
        raise OSError("simulated flush failure")


DEFAULT_FRAGMENT = object()


def response(fragment=DEFAULT_FRAGMENT, **envelope):
    if fragment is DEFAULT_FRAGMENT:
        fragment = {
            "id": FRAGMENT_ID,
            "workspaceId": WORKSPACE_ID,
            "title": "Policy",
            "content": "complete\ncontent",
        }
    body = {"success": True, "fragment": fragment}
    body.update(envelope)
    encoded = json.dumps(body).encode()
    return FakeResponse(encoded, {"Content-Length": str(len(encoded))})


class FragmentReadTests(unittest.TestCase):
    def test_uuid_only_fixed_https_get_returns_full_content(self):
        opener = FakeOpener([response()])
        result = reader.read_fragment(
            FRAGMENT_ID,
            "test-only-token",
            WORKSPACE_ID,
            opener=opener,
            sleeper=lambda _seconds: None,
        )
        self.assertEqual(result["content"], "complete\ncontent")
        request, timeout = opener.calls[0]
        self.assertEqual(request.full_url, "https://usable.dev/api/memory-fragments/" + FRAGMENT_ID)
        self.assertEqual(request.get_method(), "GET")
        self.assertIsNone(request.data)
        self.assertEqual(timeout, reader.REQUEST_TIMEOUT_SECONDS)
        self.assertEqual(request.headers["Authorization"], "Bearer test-only-token")

    def test_invalid_uuid_workspace_or_token_never_sends(self):
        opener = FakeOpener([])
        invalid = [
            ("x", "token", WORKSPACE_ID),
            (FRAGMENT_ID + "/../other", "token", WORKSPACE_ID),
            (FRAGMENT_ID, "", WORKSPACE_ID),
            (FRAGMENT_ID, "token", "not-a-uuid"),
        ]
        for fragment_id, token, workspace_id in invalid:
            with self.subTest(fragment_id=fragment_id, workspace_id=workspace_id):
                with self.assertRaises(ValueError):
                    reader.read_fragment(fragment_id, token, workspace_id, opener=opener)
        self.assertEqual(opener.calls, [])

    def test_overloaded_lookup_and_pagination_fields_are_not_accepted(self):
        with self.assertRaises(TypeError):
            reader.read_fragment(FRAGMENT_ID, "token", WORKSPACE_ID, key="x")
        with self.assertRaises(TypeError):
            reader.read_fragment(FRAGMENT_ID, "token", WORKSPACE_ID, startLine=1, endLine=2, offset=0, limit=2)

    def test_cli_failure_does_not_log_token_or_response_body(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = str(Path(directory) / "ledger.jsonl")
            stderr = io.StringIO()
            environment = {
                "USABLE_API_TOKEN": "do-not-print-this",
                "WORKSPACE_ID": WORKSPACE_ID,
                "USABLE_GROUNDING_LEDGER": ledger,
            }
            with mock.patch.dict(os.environ, environment, clear=False):
                with redirect_stderr(stderr):
                    result = reader.main(["not-a-uuid"])
            self.assertEqual(result, 1)
            self.assertNotIn("do-not-print-this", stderr.getvalue())
            self.assertNotIn("response body", stderr.getvalue())
            self.assertEqual(json.loads(Path(ledger).read_text())["fragment_id"], "invalid-input")

    def test_cli_rejects_extra_args_and_cannot_select_an_alternate_ledger(self):
        with tempfile.TemporaryDirectory() as directory:
            canonical = Path(directory) / "canonical.jsonl"
            alternate = Path(directory) / "alternate.jsonl"
            environment = {
                "WORKSPACE_ID": WORKSPACE_ID,
                "USABLE_GROUNDING_LEDGER": str(canonical),
            }
            with mock.patch.dict(os.environ, environment, clear=False), redirect_stderr(io.StringIO()):
                result = reader.main([FRAGMENT_ID, "--ledger", str(alternate)])
            self.assertEqual(result, 2)
            self.assertFalse(alternate.exists())
            self.assertEqual(
                json.loads(canonical.read_text()),
                {"fragment_id": "invalid-input", "status": "failed", "error": "invalid_invocation"},
            )

    def test_success_is_not_recorded_when_stdout_flush_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = Path(directory) / "ledger.jsonl"
            environment = {
                "WORKSPACE_ID": WORKSPACE_ID,
                "USABLE_GROUNDING_LEDGER": str(ledger),
            }
            fragment = {
                "id": FRAGMENT_ID,
                "title": "Policy",
                "workspaceId": WORKSPACE_ID,
                "updatedAt": None,
                "content": "private fragment body",
            }
            with mock.patch.dict(os.environ, environment, clear=False), \
                 mock.patch.object(reader, "read_fragment", return_value=fragment), \
                 mock.patch.object(reader.sys, "stdout", FlushFailure()), \
                 redirect_stderr(io.StringIO()):
                result = reader.main([FRAGMENT_ID])
            self.assertEqual(result, 1)
            records = [json.loads(line) for line in ledger.read_text().splitlines()]
            self.assertEqual([record["status"] for record in records], ["pending", "failed"])
            self.assertEqual(records[1]["error"], "local_io_error")
            self.assertEqual(records[0]["attempt_id"], records[1]["attempt_id"])

    def test_wrong_identity_workspace_and_malformed_envelopes_fail_closed(self):
        bad_fragments = [
            None,
            [],
            {},
            {"id": 123, "workspaceId": WORKSPACE_ID, "content": "x"},
            {"id": "11111111-1111-4111-8111-111111111111", "workspaceId": WORKSPACE_ID, "content": "x"},
            {"id": FRAGMENT_ID, "workspaceId": "11111111-1111-4111-8111-111111111111", "content": "x"},
            {"id": FRAGMENT_ID, "workspaceId": WORKSPACE_ID, "content": None},
            {"id": FRAGMENT_ID, "workspaceId": WORKSPACE_ID, "content": "x", "isPartial": True},
        ]
        for fragment in bad_fragments:
            with self.subTest(fragment=fragment):
                with self.assertRaises(ValueError):
                    reader.read_fragment(
                        FRAGMENT_ID,
                        "token",
                        WORKSPACE_ID,
                        opener=FakeOpener([response(fragment=fragment)]),
                    )
        for body in [{}, {"success": False, "fragment": {}}, {"success": True}, []]:
            encoded = json.dumps(body).encode()
            with self.subTest(body=body):
                with self.assertRaises(ValueError):
                    reader.read_fragment(
                        FRAGMENT_ID,
                        "token",
                        WORKSPACE_ID,
                        opener=FakeOpener([FakeResponse(encoded)]),
                    )

    def test_redirects_are_refused_and_not_retried(self):
        error = urllib.error.HTTPError(
            "https://usable.dev/api/memory-fragments/" + FRAGMENT_ID,
            302,
            "Found",
            {"Location": "https://evil.example/steal"},
            None,
        )
        opener = FakeOpener([error])
        with self.assertRaises(reader.FragmentReadError) as raised:
            reader.read_fragment(FRAGMENT_ID, "token", WORKSPACE_ID, opener=opener)
        self.assertEqual(raised.exception.code, "redirect_refused")
        self.assertEqual(len(opener.calls), 1)
        self.assertIsNone(reader.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.example"))

    def test_oversized_or_malformed_responses_fail_without_truncating(self):
        too_large = reader.MAX_RESPONSE_BYTES + 1
        oversized_header = FakeResponse(b"{}", {"Content-Length": str(too_large)})
        oversized_body = FakeResponse(b"x" * too_large)
        malformed = FakeResponse(b"not-json")
        for candidate in [oversized_header, oversized_body, malformed]:
            with self.subTest(candidate=candidate):
                with self.assertRaises(reader.FragmentReadError):
                    reader.read_fragment(
                        FRAGMENT_ID,
                        "token",
                        WORKSPACE_ID,
                        opener=FakeOpener([candidate]),
                    )

    def test_only_transient_failures_are_retried_with_a_bound(self):
        transient_http = urllib.error.HTTPError("https://usable.dev", 503, "Unavailable", {}, None)
        transient_network = urllib.error.URLError(socket.timeout("timed out"))
        sleeps = []
        opener = FakeOpener([transient_http, transient_network, response()])
        result = reader.read_fragment(
            FRAGMENT_ID,
            "token",
            WORKSPACE_ID,
            opener=opener,
            sleeper=sleeps.append,
            max_retries=2,
        )
        self.assertEqual(result["id"], FRAGMENT_ID)
        self.assertEqual(len(opener.calls), 3)
        self.assertEqual(sleeps, [1, 2])

        permanent = urllib.error.HTTPError("https://usable.dev", 404, "Missing", {}, None)
        opener = FakeOpener([permanent])
        with self.assertRaises(reader.FragmentReadError) as raised:
            reader.read_fragment(FRAGMENT_ID, "token", WORKSPACE_ID, opener=opener, max_retries=5)
        self.assertEqual(raised.exception.code, "http_404")
        self.assertEqual(len(opener.calls), 1)

    def test_truncated_chunked_read_after_success_is_recorded_incomplete(self):
        ledger_path = {}
        observed_statuses = []

        class TruncatedChunkHandler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                observed_statuses.extend(
                    json.loads(line)["status"]
                    for line in ledger_path["value"].read_text().splitlines()
                )
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                self.wfile.write(b"20\r\n{\"success\":true,\"fragment\":{\r\n")
                self.wfile.flush()
                self.connection.shutdown(socket.SHUT_WR)

            def log_message(self, format, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), TruncatedChunkHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                ledger = Path(directory) / "ledger.jsonl"
                ledger_path["value"] = ledger
                required = Path(directory) / "required.txt"
                required.write_text(FRAGMENT_ID + "\n")
                ledger.write_text(json.dumps({
                    "fragment_id": FRAGMENT_ID,
                    "status": "success",
                }) + "\n")
                environment = {
                    "USABLE_API_TOKEN": "test-only-token",
                    "WORKSPACE_ID": WORKSPACE_ID,
                    "USABLE_GROUNDING_LEDGER": str(ledger),
                }
                origin = f"http://127.0.0.1:{server.server_port}"
                with mock.patch.dict(os.environ, environment, clear=False), \
                     mock.patch.object(reader, "API_ORIGIN", origin), \
                     mock.patch.object(reader, "DEFAULT_MAX_RETRIES", 0), \
                     redirect_stderr(io.StringIO()):
                    result = reader.main([FRAGMENT_ID])
                self.assertEqual(result, 1)
                records = [json.loads(line) for line in ledger.read_text().splitlines()]
                self.assertEqual(records[-2]["status"], "pending")
                self.assertEqual(records[-1]["status"], "failed")
                self.assertEqual(records[-1]["error"], "protocol_error")
                self.assertEqual(records[-2]["attempt_id"], records[-1]["attempt_id"])
                evaluated = grounding_ledger.evaluate(required, ledger)
                self.assertEqual(evaluated["status"], "incomplete")
                self.assertEqual(evaluated["failed_attempts"], [FRAGMENT_ID])
                self.assertEqual(observed_statuses, ["success", "pending"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
