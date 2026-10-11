#!/usr/bin/env python3
"""Compare recorded full/delta payloads and same-clock native state age."""

import argparse
import bisect
import csv
import datetime
import json
import math
from pathlib import Path
import re


def rows(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


def distribution(values):
    values = sorted(values)
    if not values:
        return None
    return {
        "samples": len(values),
        "mean": round(sum(values) / len(values), 3),
        "p95": round(values[math.ceil(0.95 * len(values)) - 1], 3),
        "max": round(values[-1], 3),
    }


def analyze(output, clock):
    offset = clock["utc_ms"] - clock["tick_ms"]
    host = rows(output / "host-samples.csv")
    ticks = [int(x["tick"]) for x in host]
    if ticks != sorted(ticks):
        raise ValueError("Host tick samples are not monotonic")
    text = (output / "engine/host/log.txt").read_text(errors="replace")
    phases = [
        (int(t), n) for n, t in re.findall(r"DELIRIUM_PERF PHASE name=(\S+) now_ms=(\d+)", text)
    ]
    ranges = {
        name: (start, phases[i + 1][0])
        for i, (start, name) in enumerate(phases[:-1])
        if name.startswith("combat") or name == "recovery"
    }

    def source_time(tick):
        index = bisect.bisect_left(ticks, tick)
        if not 0 < index < len(ticks) or ticks[index] == ticks[index - 1]:
            return None
        before, after = host[index - 1], host[index]
        return float(before["now_ms"]) + (tick - ticks[index - 1]) * (
            float(after["now_ms"]) - float(before["now_ms"])
        ) / (ticks[index] - ticks[index - 1])

    def phase_at(now):
        return next((n for n, (a, b) in ranges.items() if a <= now < b), None)

    report = {"clock_alignment": clock, "peers": {}, "payloads": {}, "relay": {}}
    ages = []
    for role in ("host", "client", "client2", "client3"):
        if not (output / f"{role}-samples.csv").exists():
            continue
        samples = rows(output / f"{role}-samples.csv")
        peer_ages = []
        if role != "host":
            for row in samples:
                source = source_time(int(row["tick"]))
                if source is None or row["phase"] not in ranges:
                    continue
                value = dict(row, role=role, view_age_ms=round(int(row["now_ms"]) - source, 1))
                peer_ages.append(value)
                ages.append(value)
        metric_path = next((output / "engine" / role / "logs").glob("*/*/performance.jsonl"))
        runtime = (metric_path.parent / "runtime.log").read_text()
        stamp = re.search(r"\[([^\]]+)\].*run_begin", runtime)[1]
        began = datetime.datetime.fromisoformat(stamp).timestamp() * 1000 - offset
        measurements = [json.loads(line) for line in metric_path.read_text().splitlines() if line]
        report["peers"][role] = {}
        for name, (start, end) in ranges.items():
            windows = [
                x
                for x in measurements
                if began + x["run_ms"] - x["elapsed_ms"] >= start and began + x["run_ms"] < end
            ]
            costs = {}
            for operation in (
                "render_interval",
                "capture",
                "apply",
                "apply.entities",
                "decode",
                "decompress",
                "poll",
                "encode",
                "compress",
                "delta.encode",
            ):
                values = [x["costs"][operation] for x in windows if operation in x["costs"]]
                if values:
                    count = sum(x["count"] for x in values)
                    costs[operation] = {
                        "mean_ms": round(sum(x["count"] * x["mean_ms"] for x in values) / count, 4),
                        "max_ms": max(x["max_ms"] for x in values),
                        "worst_window_p95_ms": max(x["p95_ms"] for x in values),
                    }
            selected = [x for x in samples if x["phase"] == name]
            result = {
                "complete_windows": len(windows),
                "costs": costs,
                "max_counters": {
                    key: max((x["counters"].get(key, 0) for x in windows), default=0)
                    for key in (
                        "queued_bytes",
                        "cached_world_bytes",
                        "world_in_flight_bytes",
                        "world_in_flight_states",
                    )
                },
            }
            if len(selected) > 1:
                duration = (int(selected[-1]["now_ms"]) - int(selected[0]["now_ms"])) / 1000
                counter = "tick" if role == "host" else "snapshots"
                result["host_tick_hz" if role == "host" else "applied_hz"] = round(
                    (int(selected[-1][counter]) - int(selected[0][counter])) / duration, 3
                )
            if role != "host":
                result["view_age_ms"] = distribution(
                    [float(x["view_age_ms"]) for x in peer_ages if x["phase"] == name]
                )
                result["ping_ms"] = distribution([int(x["ping"]) for x in selected])
            report["peers"][role][name] = result

    payloads = {name: {"states": 0, "deltas": 0, "wire": 0, "full_wire": 0} for name in ranges}
    replays = sorted(output.glob("replay-*/states.csv"))
    for replay in replays:
        for row in rows(replay):
            source = source_time(int(row["tick"]))
            name = phase_at(source) if source is not None else None
            if name:
                value = payloads[name]
                value["states"] += 1
                value["deltas"] += int(row["delta"])
                value["wire"] += int(row["wire"])
                value["full_wire"] += int(row["full_wire"])
    for name, value in payloads.items():
        if not value["states"]:
            continue
        seconds = (ranges[name][1] - ranges[name][0]) / 1000
        value["reduction_percent"] = round(100 * (1 - value["wire"] / value["full_wire"]), 3)
        value["actual_mbps"] = round(value["wire"] * 8 / seconds / 1e6, 4)
        value["full_mbps"] = round(value["full_wire"] * 8 / seconds / 1e6, 4)
        value["per_peer_hz"] = round(value["states"] / len(replays) / seconds, 3)
        report["payloads"][name] = value

    relay_path = output / "engine/relay-samples.json"
    if relay_path.exists():
        relay = json.loads(relay_path.read_text())
        for name, (start, end) in ranges.items():
            windows = [
                (a, b)
                for a, b in zip(relay, relay[1:])
                if start <= a["utc_ms"] - offset and b["utc_ms"] - offset < end
            ]
            report["relay"][name] = distribution(
                [
                    (b["downstream_bytes"] - a["downstream_bytes"])
                    * 8
                    / (b["utc_ms"] - a["utc_ms"])
                    / 1000
                    for a, b in windows
                ]
            )
    if ages:
        with (output / "view-age.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=ages[0].keys())
            writer.writeheader()
            writer.writerows(ages)
    (output / "native-analysis.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--clock", type=Path, required=True, help="Windows tick_ms/utc_ms calibration JSON"
    )
    args = parser.parse_args()
    print(json.dumps(analyze(args.output, json.loads(args.clock.read_text())), indent=2))


if __name__ == "__main__":
    main()
