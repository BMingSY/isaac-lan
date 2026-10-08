#!/usr/bin/env python3
"""Check rendered movement and native camera drift under physical inputs."""

import argparse
import csv
import json
from pathlib import Path


def check(path):
    rows = list(csv.reader(path.open()))
    groups = {
        name: [] for name in ("large-position", "large-camera", "mirror-left", "mirror-right")
    }
    steady = 0
    for previous, current in zip(rows, rows[1:]):
        if len(previous) != 9 or len(current) != 9:
            continue
        button = int(current[8])
        stable = current[7] == previous[7] and button == int(previous[8]) and button in (1, 2, 4, 8)
        steady = steady + 1 if stable else 0
        if not stable:
            continue
        axis = 2 if button in (4, 8) else 3
        direction = 1 if button in (2, 8) else -1
        mirror = current[7] == "true"
        if mirror and axis == 2:
            direction *= -1
        move = (float(current[axis]) - float(previous[axis])) * direction
        if mirror:
            groups["mirror-left" if direction < 0 else "mirror-right"].append(move)
        elif 100 <= int(current[1]) < 350 and steady > 6:
            groups["large-position"].append(move)
            # WorldToScreen(0) contains the native camera's rendered offset.
            # Following the player translates the room in the opposite direction.
            groups["large-camera"].append(
                -(float(current[axis + 2]) - float(previous[axis + 2])) * direction
            )
    result = {
        "pass": True,
        "render_samples": len(rows),
        "movement": {},
        "visual_review_required": True,
    }
    for name, values in groups.items():
        if len(values) < 15:
            raise RuntimeError("Insufficient render samples for " + name)
        measure = {
            "samples": len(values),
            "max_reverse_step": max(0, -min(values)),
            "max_absolute_step": max(map(abs, values)),
        }
        result["movement"][name] = measure
        result["pass"] &= measure["max_reverse_step"] < 2 and measure["max_absolute_step"] < 24
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recording", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = check(args.recording)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if not result["pass"]:
        raise SystemExit(1)
