#!/usr/bin/env python3
"""Validate shared layered encoding and room pricing with four protected native games."""

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
    parser.add_argument("--extra-client", type=Path, action="append", required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=34600)
    parser.add_argument("--seconds", type=int, default=15)
    parser.add_argument("--tears", type=int, default=200)
    parser.add_argument("--baseline", action="store_true", help="Expect the old ordinary-room scan")
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    if (
        not 1024 <= args.port <= 65534
        or not 10 <= args.seconds <= 60
        or not 100 <= args.tears <= 200
    ):
        parser.error("Require port 1024..65534, seconds 10..60 and tears 100..200")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client, *args.extra_client], output, count=4)
    idle(labs, exclusive=True)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output, roles=("host", "client", "client2", "client3"))
    report = {"passed": False, "protected": protected.report(), "baseline": args.baseline}
    try:
        script = output / "fixture.lua"
        script.write_text(
            f"_IsaacLanSharedViewFixture = {{ seconds = {args.seconds}, tears = {args.tears}, "
            f"baseline = {str(args.baseline).lower()} }}\n"
            + (ROOT / "tests/state_shared_view_encoding.lua").read_text()
        )
        command = engine_command(
            labs,
            args.build,
            output / "engine",
            script,
            "LAN_SHARED_VIEW PASS native shared encoding and prices",
            "--frontend",
            "--no-luadebug",
            "--menu-start",
            "--virtual-input",
            "--automatic",
            "--menu-port",
            str(args.port),
            "--scenario-timeout",
            str(180 + args.seconds * 2),
            "--performance",
        )
        for lab in labs[2:]:
            command.extend(("--extra-client", str(lab)))
        if args.heap_check:
            command.append("--heap-check")
        report["command"] = command
        with (output / "engine.log").open("w") as log:
            result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        report["returncode"] = result.returncode
        result_path = output / "engine/result.json"
        if result_path.is_file():
            report["result"] = json.loads(result_path.read_text())
        report["passed"] = result.returncode == 0 and report.get("result", {}).get("pass") is True
        idle(labs, exclusive=True)
    finally:
        finish_run(protected, report, output)
    return 0 if report["passed"] and report["restored"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
