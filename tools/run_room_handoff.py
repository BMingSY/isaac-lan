#!/usr/bin/env python3
"""Measure door handoffs and their local overlay with a protected pair and normal input."""

import argparse
import json
from pathlib import Path
import statistics
import subprocess

from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup
from testing.engine import configure_interrupts, engine_command, run_engine
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("host", "client", "build", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--latency-ms", type=int, default=75)
    parser.add_argument("--port", type=int, default=31980)
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    if not 0 <= args.latency_ms <= 500 or not 1024 <= args.port <= 65535:
        parser.error("Invalid latency or port")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs, exclusive=True)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output)
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        ROOT / "tests/state_room_handoff.lua",
        "LAN_NETWORK HANDOFF PASS ordinary door walks and reveal completion",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--menu-port",
        str(args.port),
        "--latency-ms",
        str(args.latency_ms),
        "--scenario-timeout",
        "240",
    )
    if args.record:
        command += ["--native-record-both", "--frame-ms", "16"]
    if args.heap_check:
        command.append("--heap-check")
    report = {
        "passed": False,
        "protected": protected.report(),
        "command": command,
        "recorded": args.record,
    }
    try:
        with (output / "runner.log").open("w") as log:
            report["returncode"] = run_engine(
                command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT
            ).returncode
        result = json.loads((output / "engine/result.json").read_text())
        report["engine"] = result
        samples = {}
        for role in ("host", "client"):
            text = (output / "engine" / role / "log.txt").read_text(errors="replace")
            samples[role] = [
                json.loads(line.split("LAN_HANDOFF ", 1)[1])
                for line in text.splitlines()
                if "LAN_HANDOFF " in line
            ]
        report["observations"] = samples
        reveals = [item for item in samples["client"] if item["event"] == "result"]
        report["passed"] = result["pass"] and len(reveals) == 6
        report["timings"] = (
            {
                key: {
                    "median": statistics.median(item[key] for item in reveals),
                    "max": max(item[key] for item in reveals),
                }
                for key in (
                    "total_ms",
                    "ready_ms",
                    "hold_ms",
                    "wait_ms",
                    "native_ms",
                    "apply_ms",
                    "draw_wait_ms",
                    "reveal_ms",
                    "black_ms",
                )
            }
            if reveals
            else {}
        )
    finally:
        finish_run(protected, report, output)
    print(json.dumps({key: report.get(key) for key in ("passed", "restored", "timings")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
