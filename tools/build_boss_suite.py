#!/usr/bin/env python3
"""Command-line entry for the shared bosses suite builder."""

import argparse
from pathlib import Path
from testing.bosses import build


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shards", type=int, default=1)
    parser.add_argument("--case", action="append")
    args = parser.parse_args()
    build(args.output, args.shard, args.shards, args.case)
