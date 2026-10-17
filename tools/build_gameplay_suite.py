#!/usr/bin/env python3
"""Command-line entry for the shared gameplay suite builder."""

import argparse
from pathlib import Path
import json
from testing.gameplay import build, CASES, RESPONSE_CASES


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--cases", nargs="+", choices=[case[0] for case in [*CASES, *RESPONSE_CASES]]
    )
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(json.dumps(build(args.output, args.cases), indent=2))
