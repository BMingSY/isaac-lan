#!/usr/bin/env python3
"""Validate teleport chat commands with one protected native pair."""

import argparse
import json
from pathlib import Path
import subprocess

from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup
from testing.engine import configure_interrupts, engine_command, run_engine
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=34300)
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--record", action="store_true")
    parser.add_argument(
        "--injected", action="store_true", help="Use explicit injection in owned labs"
    )
    args = parser.parse_args()
    if not 1024 <= args.port <= 65534:
        parser.error("--port needs a second adjacent relay port")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output)
    report = {"passed": False, "protected": protected.report()}
    try:
        command = engine_command(
            labs,
            args.build,
            output / "engine",
            ROOT / "tests/state_teleport.lua",
            "LAN_TP PASS teleport commands",
            "--frontend",
            "--no-luadebug",
            "--menu-start",
            "--virtual-input",
            "--menu-port",
            str(args.port),
            "--latency-ms",
            "40",
            "--scenario-timeout",
            "240",
            "--no-performance",
        )
        if not args.injected:
            command.append("--automatic")
        if args.heap_check:
            command.append("--heap-check")
        if args.record:
            command.extend(("--native-record-both", "--frame-ms", "250"))
        report["command"] = command
        with (output / "engine.log").open("w") as log:
            result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        report["returncode"] = result.returncode
        result_path = output / "engine/result.json"
        if result_path.is_file():
            report["result"] = json.loads(result_path.read_text())
        report["passed"] = result.returncode == 0 and report.get("result", {}).get("pass") is True
    finally:
        finish_run(protected, report, output)
    return 0 if report["passed"] and report["restored"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
