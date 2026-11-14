#!/usr/bin/env python3
"""OpenAI-compatible stub provider for integration tests: fixed reply."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(n).decode() or "{}")
        last = body.get("messages", [{}])[-1].get("content", "")
        resp = json.dumps({
            "choices": [{"message": {
                "content": "echo from the stub provider: " + last[-80:]}}]
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)


ThreadingHTTPServer(("127.0.0.1", 18991), Handler).serve_forever()
