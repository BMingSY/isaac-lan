#!/usr/bin/env python3
"""Summarize bounded periodic metrics without mistaking asset loading for leaks."""

import argparse
import json
import math
from pathlib import Path


def extent(values):
    values = [value for value in values if value is not None]
    if not values:
        return None
    if any(
        not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0
        for value in values
    ):
        raise ValueError("Invalid performance measurement")
    return {"first": values[0], "last": values[-1], "min": min(values), "max": max(values)}


def summarize(path):
    samples = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    result = {
        "samples": len(samples),
        "duration_ms": sum(sample["elapsed_ms"] for sample in samples),
    }
    for name in ("private_bytes", "working_set_bytes", "handles", "cpu_core_percent"):
        result[name] = extent([sample.get(name) for sample in samples])
    counters = {name for sample in samples for name in sample.get("counters", {})}
    result["counters"] = {
        name: extent([sample.get("counters", {}).get(name) for sample in samples])
        for name in sorted(counters)
    }
    names = {name for sample in samples for name in sample.get("costs", {})}
    result["costs"] = {}
    for name in sorted(names):
        windows = [sample["costs"][name] for sample in samples if name in sample.get("costs", {})]
        count = sum(window["count"] for window in windows)
        result["costs"][name] = {
            "count": count,
            "mean_ms": sum(window["mean_ms"] * window["count"] for window in windows) / count
            if count
            else 0,
            "max_ms": max(window["max_ms"] for window in windows),
            # Per-window percentiles cannot be merged into one true percentile.
            "worst_window_p95_ms": max(window["p95_ms"] for window in windows),
            "worst_window_p99_ms": max(window["p99_ms"] for window in windows),
        }
    return result


def summarize_tree(root):
    return {
        str(path.relative_to(root)): summarize(path)
        for path in sorted(root.rglob("performance.jsonl"))
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = json.dumps(summarize_tree(args.directory), indent=2) + "\n"
    if args.output:
        args.output.write_text(report)
    else:
        print(report, end="")


if __name__ == "__main__":
    main()
