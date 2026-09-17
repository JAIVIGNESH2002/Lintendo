from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Black Mesa systems operational\n")
        else:
            self.send_response(404)
            self.end_headers()


HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

