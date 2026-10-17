#!/usr/bin/env python3
"""Command-line entry for the shared special_routes suite builder."""

import argparse
from pathlib import Path
from testing.special_routes import build, CASES, DIAGNOSTICS


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", choices=CASES + DIAGNOSTICS, action="append")
    parser.add_argument("--first-floor", action="store_true")
    args = parser.parse_args()
    build(args.output, args.case or CASES, first_floor=args.first_floor)
