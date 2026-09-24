from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


CONFIG_PATH = Path("/etc/blackmesa/telemetry.conf")


def read_config():
    config = {}
    for line in CONFIG_PATH.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator:
            raise RuntimeError(f"invalid config line: {line}")
        config[key.strip()] = value.strip()
    if config.get("enabled") != "true":
        raise RuntimeError("telemetry is not enabled")
    return config


CONFIG = read_config()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(
                f"Black Mesa telemetry operational: {CONFIG['site']}\n".encode()
            )
        else:
            self.send_response(404)
            self.end_headers()


HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

