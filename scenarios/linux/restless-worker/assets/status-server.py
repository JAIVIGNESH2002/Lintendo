import os
import sys
import time
from pathlib import Path


MODE = os.environ.get("BLACKMESA_WORKER_MODE")
INCOMING = Path(os.environ.get("BLACKMESA_INCOMING_DIR", "/var/lib/blackmesa/incoming"))
PROCESSED = Path(os.environ.get("BLACKMESA_PROCESSED_DIR", "/var/lib/blackmesa/processed"))


def fail(message):
    print(f"restless-worker: {message}", file=sys.stderr, flush=True)
    raise SystemExit(2)


if MODE != "process":
    fail("BLACKMESA_WORKER_MODE must be set to process")

if not INCOMING.is_dir():
    fail(f"incoming directory missing: {INCOMING}")

if not PROCESSED.is_dir():
    fail(f"processed directory missing: {PROCESSED}")

print("restless-worker: started", flush=True)

while True:
    for job in sorted(INCOMING.glob("*.job")):
        if not job.is_file():
            continue
        payload = job.read_text().strip()
        result = PROCESSED / f"{job.stem}.done"
        result.write_text(f"processed:{payload}\n")
        job.unlink()
        print(f"restless-worker: processed {job.name}", flush=True)
    time.sleep(1)

