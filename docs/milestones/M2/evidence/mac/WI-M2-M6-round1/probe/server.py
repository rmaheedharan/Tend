import http.server, json, sys, time, os
log = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n)
        rec = {"path": self.path, "headers": [[k, v] for k, v in self.headers.items()], "body_len": len(body),
               "body_sha": __import__('hashlib').sha256(body).hexdigest()}
        with open(log, 'a') as f: f.write(json.dumps(rec) + "\n")
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        self.wfile.write(b'data: {"x":1}\n\n'); self.wfile.flush()
        time.sleep(1.5)
        if os.environ.get('ECHO_KEY'):
            self.wfile.write(('data: ' + self.headers.get('x-api-key', '') + '\n\n').encode())
        self.wfile.write(b'data: [DONE]\n\n')
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
