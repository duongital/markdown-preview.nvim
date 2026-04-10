#!/usr/bin/env python3
"""
Demo server for markdown-preview.nvim

Serves assets/index.html with .github/copilot-instructions.md as content,
so you can iterate on the HTML/CSS without needing Neovim running.

Usage:
    python3 demo/server.py          # default port 3000
    python3 demo/server.py 8080     # custom port
"""

import http.server
import socketserver
import sys
import time
from pathlib import Path

ROOT = Path(__file__).parent.parent
ASSETS = ROOT / "assets"
CONTENT = ROOT / ".github" / "copilot-instructions.md"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 3000


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"  {args[0]:7} {args[1]}")

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self._serve_file(ASSETS / "index.html", "text/html; charset=utf-8")
        elif path == "/index.css":
            self._serve_file(ASSETS / "index.css", "text/css; charset=utf-8")
        elif path == "/content.md":
            self._serve_file(CONTENT, "text/plain; charset=utf-8")
        elif path == "/__live/events":
            self._serve_sse()
        else:
            self.send_response(404)
            self.end_headers()

    def _serve_file(self, path, content_type):
        try:
            data = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()

    def _serve_sse(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        # Keep connection alive; browser shows "connected" status dot
        try:
            while True:
                self.wfile.write(b": heartbeat\n\n")
                self.wfile.flush()
                time.sleep(15)
        except (BrokenPipeError, ConnectionResetError):
            pass


class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    server = ThreadedServer(("localhost", PORT), Handler)
    print(f"\n  Demo server  →  http://localhost:{PORT}")
    print(f"  Content      →  {CONTENT.relative_to(ROOT)}\n")
    print("  Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
