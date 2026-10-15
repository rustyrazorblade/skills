"""Stub Grafana for test-report.sh: answers the render API and the dashboard API.

Usage: python3 stub.py <mode> <port-file> <request-log> [<dashboard.json>]

It binds 127.0.0.1 on a free port and writes the port to <port-file>.  It appends one line per
request to <request-log>: the path with its query string.

A GET on /render/... answers by <mode>:
  png     status 200 with the bytes of panel.png, next to this file
  500     status 500 with a short text body
  empty   status 200 with an empty body
  notpng  status 200 with an HTML body, as a login page gives

A GET on /api/dashboards/uid/<UID> answers status 200 with <dashboard.json>, or status 404 when
no file is given.  Stdlib only, so it needs no uv environment.
"""

import http.server
import os
import sys

mode, port_file, log_path = sys.argv[1:4]
dashboard_path = sys.argv[4] if len(sys.argv) > 4 else None
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "panel.png"), "rb") as f:
    png = f.read()

RENDER = {
    "png": (200, "image/png", png),
    "500": (500, "text/plain", b"rendering failed"),
    "empty": (200, "image/png", b""),
    "notpng": (200, "text/html", b"<html><body>Grafana login</body></html>"),
}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(log_path, "a") as log:
            log.write(f"{self.path}\n")
        if self.path.startswith("/api/dashboards/uid/"):
            if dashboard_path:
                with open(dashboard_path, "rb") as f:
                    self.answer(200, "application/json", f.read())
            else:
                self.answer(404, "application/json", b'{"message":"Dashboard not found"}')
        elif self.path.startswith("/render/"):
            self.answer(*RENDER[mode])
        else:
            self.answer(404, "text/plain", b"not found")

    def answer(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
