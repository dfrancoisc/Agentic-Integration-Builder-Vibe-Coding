"""Simple HTTP proxy that forwards every request to the iris-agentic
container (localhost:22773). Used only by the preview tool — do not ship.

Adds Basic auth automatically so the preview iframe doesn't get stopped
by IRIS's login challenge on /ui/interop/* (the customer's portal will
already be authenticated; the preview is just a shortcut).

Default URL on start: http://127.0.0.1:8088/agentic/index.html
"""
import base64
import http.server
import http.client
import sys

UPSTREAM_HOST = "localhost"
UPSTREAM_PORT = 22773
USER = "_SYSTEM"
PASS = "Agentic1!"
BASIC = "Basic " + base64.b64encode(f"{USER}:{PASS}".encode()).decode()


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def _proxy(self, method):
        body = None
        length = self.headers.get("Content-Length")
        if length:
            body = self.rfile.read(int(length))
        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=30)
        fwd = {}
        for k, v in self.headers.items():
            if k.lower() in ("host", "connection", "content-length",
                             "transfer-encoding", "authorization"):
                continue
            fwd[k] = v
        fwd["Authorization"] = BASIC
        try:
            conn.request(method, self.path, body=body, headers=fwd)
            resp = conn.getresponse()
            data = resp.read()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() in ("transfer-encoding", "connection", "content-length"):
                    continue
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as exc:  # noqa: BLE001
            self.send_error(502, f"proxy upstream error: {exc}")
        finally:
            conn.close()

    def do_GET(self):    self._proxy("GET")
    def do_POST(self):   self._proxy("POST")
    def do_PUT(self):    self._proxy("PUT")
    def do_DELETE(self): self._proxy("DELETE")
    def do_OPTIONS(self): self._proxy("OPTIONS")

    def log_message(self, fmt, *args):
        sys.stderr.write("[proxy] " + (fmt % args) + "\n")


def main():
    port = 8088
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), ProxyHandler)
    sys.stderr.write(f"[proxy] forwarding 127.0.0.1:{port} -> {UPSTREAM_HOST}:{UPSTREAM_PORT}\n")
    sys.stderr.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
