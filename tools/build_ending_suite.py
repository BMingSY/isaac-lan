#!/usr/bin/env python3
"""Build the native ending-route fixture, optionally selecting diagnostic routes."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def build(output, routes=None):
    endings = (ROOT / "tests/state_endings.lua").read_text()
    if routes:
        endings = endings.replace(
            'local cases = { "lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent" }',
            "local cases = { " + ", ".join(json.dumps(route) for route in routes) + " }",
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(endings)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.output)
