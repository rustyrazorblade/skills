"""Stub Mimir for test-report.sh: answers every GET with one canned JSON response.

Usage: python3 stub.py <response.json> <http-status> <port-file> <request-log>

It binds 127.0.0.1 on a free port and writes the port to <port-file>.  It appends one line per
request to <request-log>: the path with its query string, then the X-Scope-OrgID header.  Stdlib
only, so it needs no uv environment.
"""

import http.server
import sys

response_path, status, port_file, log_path = sys.argv[1:5]
with open(response_path, "rb") as f:
    body = f.read()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(log_path, "a") as log:
            log.write(f"{self.path} tenant={self.headers.get('X-Scope-OrgID', '')}\n")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
