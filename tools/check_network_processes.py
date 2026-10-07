#!/usr/bin/env python3
"""Run four independent Windows processes against the actual Winsock transport."""
import argparse
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    children = []
    records = []
    started = time.monotonic()
    try:
        host = subprocess.Popen([str(args.executable), "host", "0", "4"], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        children.append(host)
        # The executable has an internal 60 s deadline, including startup.
        line = host.stdout.readline().strip()
        if not line.startswith("LISTEN_PORT "):
            raise RuntimeError(f"Host did not bind: {line}")
        port = line.split()[1]
        for _ in range(3):
            children.append(subprocess.Popen([str(args.executable), "join", port, "4"],
                                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
        for child in children:
            output = child.communicate(timeout=65)[0].strip()
            records.append({"exit_code": child.returncode, "output": output})
        if any(record["exit_code"] or "PASS process" not in record["output"] for record in records):
            raise RuntimeError("A peer failed the independent-process test")
    finally:
        for child in children:
            if child.poll() is None:
                child.kill()
                child.wait()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({"seconds": time.monotonic() - started,
                                          "peers": records}, indent=2) + "\n")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
