#!/usr/bin/env python3
"""Replay saved Lua requests without launching the game; old outputs are diagnostic."""

import argparse
import json
from pathlib import Path

from offline_lua import LuaWorker


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    args = parser.parse_args()
    requests = json.loads(args.trace.read_text())
    worker = LuaWorker()
    try:
        for entry in requests:
            request = entry["request"]
            value = worker.call(*request)
            print(json.dumps({"request": request, "response": value}, ensure_ascii=False))
    finally:
        worker.close()


if __name__ == "__main__":
    main()
