#!/usr/bin/env python3
"""Compare native/Lua codecs offline using the production binding and identical bytes."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from testing.results import write_report

ROOT = Path(__file__).resolve().parents[1]


def summarize(samples):
    results = []
    grouped = {}
    for sample in samples:
        key = sample["case"], sample["operation"]
        entries = grouped.setdefault(key, {})
        if sample["implementation"] in entries:
            raise ValueError("Duplicate benchmark result")
        if sample["samples"] < 1 or sample["mean_ms"] < 0 or sample["p95_ms"] < 0:
            raise ValueError("Invalid benchmark measurement")
        entries[sample["implementation"]] = sample
    if not grouped:
        raise ValueError("Codec benchmark produced no measurements")
    for (case, operation), entries in grouped.items():
        if set(entries) != {"lua", "native"}:
            raise ValueError("Both implementations must complete every measurement")
        reference, native = entries["lua"], entries["native"]
        if reference["bytes"] != native["bytes"] or reference["samples"] != native["samples"]:
            raise ValueError("Codec measurements used different workloads")
        results.append(
            {
                "case": case,
                "operation": operation,
                "lua": reference,
                "native": native,
                "speedup": reference["mean_ms"] / native["mean_ms"] if native["mean_ms"] else None,
            }
        )
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", type=Path, required=True, help="Release state codec runner")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--iterations", type=int, default=100)
    parser.add_argument("--snapshot", type=Path, help="Optional decoded full wire snapshot")
    args = parser.parse_args()
    if not 5 <= args.iterations <= 10000:
        parser.error("Iterations must be between 5 and 10000")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"schema_version": 1, "status": "error", "passed": False, "game_started": False}
    try:
        runner = args.runner.resolve()
        report["runner_sha256"] = hashlib.sha256(runner.read_bytes()).hexdigest()
        report["command"] = [
            str(runner),
            str(ROOT / "tests/fixtures/codec_benchmark.lua"),
            str(ROOT),
            str(args.iterations),
        ]
        if args.snapshot:
            report["snapshot_sha256"] = hashlib.sha256(args.snapshot.read_bytes()).hexdigest()
            report["command"].append(str(args.snapshot.resolve()))
        result = subprocess.run(report["command"], capture_output=True, text=True, timeout=300)
        (output / "measurements.jsonl").write_text(result.stdout)
        (output / "stderr.log").write_text(result.stderr)
        result.check_returncode()
        report["results"] = summarize([json.loads(line) for line in result.stdout.splitlines()])
        report.update(passed=True, status="passed")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    finally:
        write_report(output, report, classname="codec")
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
