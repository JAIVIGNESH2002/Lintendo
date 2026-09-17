#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path("/opt/blackmesa/status-server.py")
text = path.read_text()
old = 'HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()'
new = 'HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()'
if old not in text:
    raise SystemExit("expected listener text was not found")
path.write_text(text.replace(old, new))
PY

systemctl restart blackmesa.service
systemctl is-active --quiet blackmesa.service

