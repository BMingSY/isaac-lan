#!/usr/bin/env python3
"""Measure native input-to-preview delay and movement on transition frames."""

import argparse
import json
from pathlib import Path


from testing.input_response import measure, passed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixed", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = {"fixed": measure(args.fixed)}
    assert passed(result["fixed"]), result
    if args.baseline:
        result["baseline"] = measure(args.baseline)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
