#!/usr/bin/env python3
"""Validate shared rule effects with one native pair, then restart for preferences."""

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
    parser.add_argument("--port", type=int, default=34200)
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--record", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65534:
        parser.error("--port needs a second adjacent relay port")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output)
    report = {"passed": False, "protected": protected.report(), "runs": []}
    scenarios = (
        ("engine", "state_shared_rules.lua", "LAN_SHARED_RULES PASS shared rules", 480),
        ("restart", "state_room_rules_preferences.lua", "LAN_PREFERENCES_PASS", 120),
    )
    try:
        for name, script, completion, timeout in scenarios:
            command = engine_command(
                labs,
                args.build,
                output / name,
                ROOT / "tests" / script,
                completion,
                "--frontend",
                "--automatic",
                "--no-luadebug",
                "--menu-start",
                "--virtual-input",
                "--menu-port",
                str(args.port),
                "--latency-ms",
                "40",
                "--scenario-timeout",
                str(timeout),
                "--no-performance",
            )
            if args.heap_check:
                command.append("--heap-check")
            if args.record:
                command.extend(("--native-record-both", "--frame-ms", "250"))
            with (output / (name + ".log")).open("w") as log:
                result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            run = {"name": name, "command": command, "returncode": result.returncode}
            report["runs"].append(run)
            result_path = output / name / "result.json"
            if result_path.is_file():
                run["result"] = json.loads(result_path.read_text())
            if result.returncode != 0:
                break
        else:
            report["passed"] = True
    finally:
        finish_run(protected, report, output)
    return 0 if report["passed"] and report["restored"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
