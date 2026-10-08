#!/usr/bin/env python3
"""Check continuous displayed movement and held-input leakage across a door."""

import argparse
import csv
import json
import math
from pathlib import Path
import statistics


def measure(path):
    with path.open() as source:
        records = list(csv.DictReader(source))
    # Closing the native process can leave its final buffered render row partial.
    if records and any(value is None for value in records[-1].values()):
        records.pop()
    rows = [{k: float(v) for k, v in row.items()} for row in records]
    speeds = []
    for previous, current in zip(rows, rows[1:]):
        dt = current["time"] - previous["time"]
        if 65 <= current["tick"] < 78 and dt > 0.008:
            speeds.append((current["x"] - previous["x"]) / dt)
    assert len(speeds) >= 20, "Continuous motion window was not exercised"
    resurgences = []
    for tick, direction in ((80, 1), (130, -1)):
        start = next(r["time"] for r in rows if r["tick"] >= tick and r["buttons"] == 0)
        minimum, resurgence = math.inf, 0
        for previous, current in zip(rows, rows[1:]):
            dt = current["time"] - previous["time"]
            if dt <= 0.008 or not 0.04 < current["time"] - start < 0.35:
                continue
            speed = (current["x"] - previous["x"]) * direction / dt
            minimum = min(minimum, speed)
            resurgence = max(resurgence, speed - minimum)
        resurgences.append(resurgence)
    source_room = next(r["room"] for r in rows if r["room"] >= 0)
    arrival = next(i for i, r in enumerate(rows) if r["room"] >= 0 and r["room"] != source_room)
    entry = rows[arrival]
    post_arrival = rows[arrival:]
    assert len(post_arrival) > 100, "Arrival settling was not observed"
    return {
        "render_samples": len(rows),
        "steady_speed_mean": statistics.mean(speeds),
        "steady_speed_stddev": statistics.pstdev(speeds),
        "max_speed_resurgence_after_release": max(resurgences),
        "max_arrival_displacement": max(
            math.hypot(r["x"] - entry["x"], r["y"] - entry["y"]) for r in post_arrival
        ),
        "rooms_after_arrival": len({r["room"] for r in post_arrival}),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixed", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = {"fixed": measure(args.fixed)}
    fixed = result["fixed"]
    assert fixed["max_speed_resurgence_after_release"] < 35, result
    assert fixed["max_arrival_displacement"] < 25 and fixed["rooms_after_arrival"] == 1, result
    if args.baseline:
        result["baseline"] = measure(args.baseline)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
