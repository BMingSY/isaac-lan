#!/usr/bin/env python3
"""Measure native input-to-preview delay and movement on transition frames."""

import argparse
import csv
import json
import math
from pathlib import Path


def measure(path):
    with path.open() as source:
        rows = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(source)]
    rows = [row for row in rows if 80 <= row["tick"] < 490]
    assert len(rows) > 500, "Insufficient native render samples"
    mismatched = 0
    unsent = 0
    delays = []
    transition_steps = []
    movement_delays = []
    releases = []
    acceleration_transitions = 0
    acceleration_responses = 0
    for i, row in enumerate(rows):
        raw = (row["raw_x"], row["raw_y"])
        preview = (row["preview_x"], row["preview_y"])
        mismatched += raw != preview
        unsent += raw != (row["sent_x"], row["sent_y"])
        if not i:
            continue
        previous = rows[i - 1]
        if raw == (previous["raw_x"], previous["raw_y"]):
            continue
        if "before_vx" in row and row["time"] > previous["time"]:
            acceleration_transitions += 1
            change_x, change_y = raw[0] - previous["raw_x"], raw[1] - previous["raw_y"]
            response = (row["after_vx"] - row["before_vx"]) * change_x + (
                row["after_vy"] - row["before_vy"]
            ) * change_y
            acceleration_responses += response > 0.01
        for later in rows[i : i + 5]:
            if (later["preview_x"], later["preview_y"]) == raw:
                delays.append((later["time"] - row["time"]) * 1000)
                break
        else:
            delays.append(math.inf)
        dx, dy = row["x"] - previous["x"], row["y"] - previous["y"]
        if raw != (0, 0):
            transition_steps.append(dx * raw[0] + dy * raw[1])
            for j in range(i, min(i + 5, len(rows))):
                a, b = rows[j - 1], rows[j]
                if (b["x"] - a["x"]) * raw[0] + (b["y"] - a["y"]) * raw[1] > 0.1:
                    movement_delays.append((b["time"] - row["time"]) * 1000)
                    break
            else:
                movement_delays.append(math.inf)
        else:
            releases.append(math.hypot(dx, dy))
    assert len(delays) >= 30 and unsent >= 12, "Unsent start/turn/release changes not exercised"
    return {
        "render_samples": len(rows),
        "transitions": len(delays),
        "frames_with_unsent_input": unsent,
        "preview_mismatched_frames": mismatched,
        "max_input_to_preview_ms": max(delays),
        "mean_input_to_preview_ms": sum(delays) / len(delays),
        "movement_transitions": len(transition_steps),
        "acceleration_transitions": acceleration_transitions,
        "acceleration_transitions_responding_same_frame": acceleration_responses,
        "movement_transitions_responding_same_frame": sum(step > 0.1 for step in transition_steps),
        "max_input_to_movement_ms": max(movement_delays),
        "mean_input_to_movement_ms": sum(movement_delays) / len(movement_delays),
        "mean_release_frame_displacement": sum(releases) / len(releases),
        "max_release_frame_displacement": max(releases),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixed", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = {"fixed": measure(args.fixed)}
    assert result["fixed"]["preview_mismatched_frames"] == 0, result
    assert result["fixed"]["max_input_to_preview_ms"] == 0, result
    assert (
        result["fixed"]["acceleration_transitions"] >= 30
        and result["fixed"]["acceleration_transitions_responding_same_frame"]
        >= 0.9 * result["fixed"]["acceleration_transitions"]
    ), result
    if args.baseline:
        result["baseline"] = measure(args.baseline)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
