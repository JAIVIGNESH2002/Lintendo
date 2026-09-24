from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse
import os
import re
import subprocess
import sys


TOKEN_RE = re.compile(r"^[A-Za-z0-9_.-]{1,80}$")


def db_env():
    env = os.environ.copy()
    env["PGPASSWORD"] = os.environ["DB_PASSWORD"]
    return env


def psql(sql):
    command = [
        "psql",
        "-h",
        os.environ.get("DB_HOST", "postgres"),
        "-U",
        os.environ.get("DB_USER", "blackmesa"),
        "-d",
        os.environ.get("DB_NAME", "payments"),
        "-v",
        "ON_ERROR_STOP=1",
        "-At",
        "-q",
        "-c",
        sql,
    ]
    output = subprocess.run(
        command,
        env=db_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout.strip()
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    return lines[-1] if lines else ""


def charge(token):
    if not TOKEN_RE.fullmatch(token):
        raise ValueError("invalid token")
    sql = f"""
CREATE TABLE IF NOT EXISTS payments (
  token text PRIMARY KEY,
  processed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO payments(token) VALUES ('{token}')
ON CONFLICT (token) DO NOTHING;
SELECT 'charged:{token}';
"""
    return psql(sql)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"payments-api online\n")
            return

        if parsed.path == "/charge":
            token = parse_qs(parsed.query).get("token", [""])[0]
            try:
                result = charge(token)
            except Exception as exc:
                self.send_response(503)
                self.end_headers()
                self.wfile.write(f"database operation failed: {exc}\n".encode())
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(f"{result}\n".encode())
            return

        self.send_response(404)
        self.end_headers()


def serve():
    port = int(os.environ.get("API_PORT", "8080"))
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "charge":
        print(charge(sys.argv[2]))
    else:
        serve()
