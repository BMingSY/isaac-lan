#!/usr/bin/env python3
"""Check last-survivor death, native game over and exit with one protected pair."""

import argparse
import json
from pathlib import Path
import subprocess

from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup, windows
from testing.engine import configure_interrupts, engine_command, run_engine
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]
COMPLETION = "LAN_NETWORK PASS game over and native exit"


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30792)
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.port < 65535:
        parser.error("Invalid port")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    coordination = output / "coordination"
    coordination.mkdir()
    (coordination / "case.txt").write_text("1")
    script = output / "suite.lua"
    script.write_text(
        "local gameOverCoordination = "
        + json.dumps(windows(coordination).replace("\\", "/"))
        + "\n"
        + (ROOT / "tests/state_game_over.lua").read_text()
    )
    protected = ProtectedLabs(labs, output)
    report = {"passed": False, "protected": protected.report()}
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        COMPLETION,
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "480",
    )
    if args.record:
        command += ["--native-record-both", "--frame-ms", "250"]
    if args.heap_check:
        command.append("--heap-check")
    report["command"] = command
    try:
        with (output / "runner.log").open("w") as log:
            report["returncode"] = run_engine(
                command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT
            ).returncode
        result = json.loads((output / "engine/result.json").read_text())
        report["engine"] = result
        report["passed"] = result["pass"] and all(
            (coordination / f"done-{case}-{role}").is_file()
            for case in range(1, 9)
            for role in ("host", "client")
        )
    finally:
        finish_run(protected, report, output)
    print(json.dumps({"passed": report["passed"], "restored": report["restored"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
