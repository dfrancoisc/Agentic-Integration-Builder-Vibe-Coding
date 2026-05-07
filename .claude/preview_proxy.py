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
    # HTTP/1.1 is required for Transfer-Encoding: chunked. Default is
    # HTTP/1.0 which forces Content-Length and breaks SSE streaming.
    protocol_version = "HTTP/1.1"
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
            ctype = resp.getheader("Content-Type", "") or ""
            is_stream = "text/event-stream" in ctype.lower()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() in ("transfer-encoding", "connection", "content-length"):
                    continue
                self.send_header(k, v)
            if is_stream:
                # SSE: forward bytes incrementally so each event reaches
                # the browser the moment IRIS emits it. Without this the
                # whole stream gets buffered and the chat looks
                # non-streaming. Use chunked encoding so we don't need
                # an upfront Content-Length.
                self.send_header("Transfer-Encoding", "chunked")
                self.send_header("Cache-Control", "no-cache, no-transform")
                self.send_header("X-Accel-Buffering", "no")
                self.end_headers()
                while True:
                    # Bigger reads, but still incremental — http.client
                    # returns whatever's available up to this size, and
                    # blocks only if nothing's there. Each arrival gets
                    # framed and flushed immediately.
                    chunk = resp.read(4096)
                    if not chunk:
                        # Final chunk (zero-length) per HTTP/1.1 chunked
                        # encoding ends the body.
                        try:
                            self.wfile.write(b"0\r\n\r\n")
                            self.wfile.flush()
                        except Exception:
                            pass
                        break
                    try:
                        self.wfile.write(f"{len(chunk):x}\r\n".encode())
                        self.wfile.write(chunk)
                        self.wfile.write(b"\r\n")
                        self.wfile.flush()
                    except Exception:
                        break
            else:
                data = resp.read()
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        except Exception as exc:  # noqa: BLE001
            try:
                self.send_error(502, f"proxy upstream error: {exc}")
            except Exception:
                pass
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
