#!/usr/bin/env python3
"""HTTPS stand-in for a live site, a deploy webhook, the GitHub API and a chat API, for the agent-deploy
tests and the tests of actions/deepseek-review and actions/deploy-webhook.

usage: mock_server.py CONFIG PORTFILE LOGFILE CERT KEY

CONFIG is re-read on every request, so a test rewrites it instead of restarting the server:
  {"routes": {"/path": RESPONSE or [RESPONSE, ...]}}
  RESPONSE = {"status": 200, "headers": {"Name": "value" or ["v1", "v2"]}, "body": "text", "json": ...,
              "short_body": true}
A list is served in order, one entry per request, and its last entry repeats. A route matches the
path with its query first, then the path alone. Unknown paths answer 404. "short_body" promises 100
bytes more than it sends, then closes the connection: a response that never completes.

Every request is appended to LOGFILE as one JSON line: method, path, headers (lower-case names),
body. Binds 127.0.0.1 on a free port and writes the port to PORTFILE.
"""
import hashlib
import http.server
import json
import os
import ssl
import sys

CONFIG, PORTFILE, LOGFILE, CERT, KEY = sys.argv[1:6]
COUNTS = {}
STATE = {"digest": None}


def load():
    with open(CONFIG, "rb") as handle:
        raw = handle.read()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != STATE["digest"]:
        STATE["digest"] = digest
        COUNTS.clear()
    return json.loads(raw or b"{}")


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def answer(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace") if length else ""
        with open(LOGFILE, "a", encoding="utf-8") as log:
            log.write(json.dumps({
                "method": self.command,
                "path": self.path,
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": body,
            }) + "\n")
        routes = load().get("routes", {})
        key = self.path if self.path in routes else self.path.split("?", 1)[0]
        spec = routes.get(key, {"status": 404, "body": "not found"})
        if isinstance(spec, list):
            index = COUNTS.get(key, 0)
            COUNTS[key] = index + 1
            spec = spec[min(index, len(spec) - 1)]
        if "json" in spec:
            payload = json.dumps(spec["json"]).encode()
            ctype = "application/json; charset=utf-8"
        else:
            payload = spec.get("body", "").encode()
            ctype = "text/html; charset=utf-8"
        self.send_response(spec.get("status", 200))
        headers = {"Content-Type": ctype}
        headers.update(spec.get("headers", {}))
        for name, value in headers.items():
            for item in value if isinstance(value, list) else [value]:
                self.send_header(name, item)
        short = bool(spec.get("short_body"))
        self.send_header("Content-Length", str(len(payload) + (100 if short else 0)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)
        if short:
            self.close_connection = True

    do_GET = do_POST = do_HEAD = do_PATCH = answer


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(CERT, KEY)
server.socket = context.wrap_socket(server.socket, server_side=True)
with open(PORTFILE + ".tmp", "w") as handle:
    handle.write(str(server.server_address[1]))
# Renamed into place after the bind, so the port file appears only once the server listens.
os.replace(PORTFILE + ".tmp", PORTFILE)
server.serve_forever()
