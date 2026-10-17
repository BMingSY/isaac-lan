#!/usr/bin/env python3
"""Command-line entry for the shared endings suite builder."""

import argparse
from pathlib import Path
from testing.endings import build, CASES


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--route", choices=CASES, action="append")
    parser.add_argument("--first-floor", action="store_true")
    args = parser.parse_args()
    build(args.output, args.route, first_floor=args.first_floor)
