#!/usr/bin/env python3
"""Build the native ending-route fixture, optionally selecting diagnostic routes."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ("lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent")


def build(output, routes=None, *, first_floor=False):
    if routes is not None and (
        not routes or len(set(routes)) != len(routes) or any(route not in CASES for route in routes)
    ):
        raise ValueError("Choose distinct known ending routes")
    endings = (ROOT / "tests/state_endings.lua").read_text()
    if routes:
        endings = endings.replace(
            'local cases = { "lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent" }',
            "local cases = { " + ", ".join(json.dumps(route) for route in routes) + " }",
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(("_IsaacLanTest.firstFloor = true\n" if first_floor else "") + endings)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--route", choices=CASES, action="append")
    parser.add_argument("--first-floor", action="store_true")
    args = parser.parse_args()
    build(args.output, args.route, first_floor=args.first_floor)
