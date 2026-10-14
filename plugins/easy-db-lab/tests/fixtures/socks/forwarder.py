"""Stub SOCKS5 proxy for test-report.sh: forwards one CONNECT per client to its target.

Usage: python3 forwarder.py <port-file> <connect-log>

It binds 127.0.0.1 on a free port and writes the port to <port-file>.  It appends one line per
CONNECT to <connect-log>: the target as host:port.  It accepts only the no-auth method and the
CONNECT command, with an IPv4 or a domain-name target, as socks5h sends.  Stdlib only, so it needs
no uv environment.
"""

import socket
import socketserver
import struct
import sys
import threading

port_file, log_path = sys.argv[1:3]


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("client closed")
        data += chunk
    return data


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        _, n_methods = recv_exact(client, 2)
        recv_exact(client, n_methods)
        client.sendall(b"\x05\x00")
        _, cmd, _, atyp = recv_exact(client, 4)
        if atyp == 1:
            host = socket.inet_ntoa(recv_exact(client, 4))
        elif atyp == 3:
            host = recv_exact(client, recv_exact(client, 1)[0]).decode()
        else:
            client.sendall(b"\x05\x08\x00\x01" + b"\x00" * 6)
            return
        (port,) = struct.unpack("!H", recv_exact(client, 2))
        if cmd != 1:
            client.sendall(b"\x05\x07\x00\x01" + b"\x00" * 6)
            return
        with open(log_path, "a") as log:
            log.write(f"{host}:{port}\n")
        upstream = socket.create_connection((host, port))
        client.sendall(b"\x05\x00\x00\x01" + b"\x00" * 6)
        t = threading.Thread(target=pipe, args=(upstream, client), daemon=True)
        t.start()
        pipe(client, upstream)
        t.join()
        upstream.close()


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True


server = Server(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
