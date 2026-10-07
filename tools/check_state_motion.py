#!/usr/bin/env python3
"""Check actual MC_POST_RENDER positions, including frames between snapshots."""
import argparse
import csv
import json
from pathlib import Path


def measure(path):
    rows = [list(map(float, row)) for row in csv.reader(path.open()) if len(row) == 6]
    steady = 0
    movement = []
    for previous, current in zip(rows, rows[1:]):
        steady = steady + 1 if current[5] and current[5] == previous[5] else 0
        # Compare the same movement window in the old failing and fixed runs.
        if steady > 6 and 40 <= current[2] <= 440:
            movement.append((current[3] - previous[3]) * current[5])
    assert len(movement) > 500, "Insufficient continuous-motion render samples"
    return {"render_samples": len(rows), "compared_samples": len(movement),
            "max_reverse_step": max(0, -min(movement)),
            "max_absolute_step": max(map(abs, movement)),
            "reverse_steps_over_two_units": sum(step < -2 for step in movement)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixed", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = {"fixed": measure(args.fixed)}
    assert result["fixed"]["max_reverse_step"] < 2, result
    if args.baseline:
        result["baseline"] = measure(args.baseline)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
