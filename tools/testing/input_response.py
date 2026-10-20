"""Shared analysis of native input-to-preview and movement samples."""

import csv
import math


def measure(path):
    lines = path.read_text(errors="replace").splitlines()
    marker = "LAN_NETWORK INPUT_RESPONSE_CSV "
    logged = [line.split(marker, 1)[1] for line in lines if marker in line]
    records = list(csv.DictReader(logged or lines))
    if records and any(value is None for value in records[-1].values()):
        records.pop()
    rows = [{k: float(v) for k, v in row.items()} for row in records]
    rows = [row for row in rows if 80 <= row["tick"] < 490]
    assert len(rows) > 500, "Insufficient native render samples"
    mismatched = 0
    unsent = 0
    send_delays = []
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
        for later in rows[i : i + 5]:
            if (later["sent_x"], later["sent_y"]) == raw:
                send_delays.append((later["time"] - row["time"]) * 1000)
                break
        else:
            send_delays.append(math.inf)
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
    assert len(delays) >= 30, "Start/turn/release changes not exercised"
    return {
        "render_samples": len(rows),
        "transitions": len(delays),
        "frames_with_unsent_input": unsent,
        "max_input_to_send_ms": max(send_delays),
        "mean_input_to_send_ms": sum(send_delays) / len(send_delays),
        "input_samples_per_render": (rows[-1]["capture"] - rows[0]["capture"]) / (len(rows) - 1),
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


def passed(result):
    return (
        result["preview_mismatched_frames"] == 0
        and result["max_input_to_preview_ms"] == 0
        and result["max_input_to_send_ms"] == 0
        and 0.95 <= result["input_samples_per_render"] <= 1.05
        and result["acceleration_transitions"] >= 30
        and result["acceleration_transitions_responding_same_frame"]
        >= 0.9 * result["acceleration_transitions"]
    )
