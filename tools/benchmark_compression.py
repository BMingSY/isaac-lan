#!/usr/bin/env python3
"""Measure real snapshot pairs with miniz, LZ4 and the production Zstd adapter."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from lab_profile import windows
from testing.results import write_report

ALGORITHMS = {"miniz-full", "lz4-full", "zstd-full", "miniz-delta", "zstd-prefix"}


def summarize(rows, iterations):
    expected = {(algorithm, players) for algorithm in ALGORITHMS for players in (2, 3, 4)}
    for row in rows:
        key = row["algorithm"], row["players"]
        if key not in expected or row["samples"] != iterations:
            raise ValueError("Duplicate, unexpected or incomplete compression measurement")
        expected.remove(key)
        if row["raw_bytes"] <= 0 or row["packed_bytes"] <= 0:
            raise ValueError("Empty compression workload")
        for operation in ("encode", "decode"):
            metrics = row[operation]
            if not 0 <= metrics["p95_ms"] <= metrics["p99_ms"] or metrics["mean_ms"] < 0:
                raise ValueError("Invalid compression timing")
    if expected:
        raise ValueError("Compression comparison is incomplete")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", type=Path, required=True)
    parser.add_argument("--pair", nargs=2, type=Path, action="append", required=True)
    parser.add_argument("--iterations", type=int, default=100)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if len(args.pair) > 3 or not 5 <= args.iterations <= 10000:
        parser.error("Supply one to three snapshot pairs and 5..10000 iterations")
    args.output.mkdir(parents=True, exist_ok=False)
    report = {"schema_version": 1, "status": "error", "passed": False, "game_started": False}
    try:
        runner = args.runner.resolve()
        paths = [path.resolve() for pair in args.pair for path in pair]
        report["inputs"] = [
            {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            for path in [runner, *paths]
        ]
        report["command"] = [
            str(runner),
            str(args.iterations),
            *[windows(path) if runner.suffix == ".exe" else str(path) for path in paths],
        ]
        result = subprocess.run(report["command"], capture_output=True, text=True, timeout=600)
        (args.output / "measurements.jsonl").write_text(result.stdout)
        (args.output / "stderr.log").write_text(result.stderr)
        result.check_returncode()
        report["results"] = summarize(
            [json.loads(line) for line in result.stdout.splitlines()], args.iterations
        )
        report.update(passed=True, status="passed")
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    finally:
        write_report(args.output, report, classname="compression")
    print(json.dumps({key: report[key] for key in ("status", "passed")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
