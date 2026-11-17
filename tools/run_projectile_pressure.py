#!/usr/bin/env python3
"""Compare complete projectile synchronization with one protected native pair."""

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
    parser.add_argument("--port", type=int, default=35640)
    parser.add_argument("--latency-ms", type=int, default=40)
    parser.add_argument(
        "--phase-profile", action="store_true", help="Enable detailed per-entity timing"
    )
    parser.add_argument(
        "--verify", action="store_true", help="Also check links, room and floor cleanup"
    )
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65534 or not 0 <= args.latency_ms <= 500:
        parser.error("Require port 1024..65534 and one-way latency 0..500 ms")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs, exclusive=not args.verify)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output)
    report = {"passed": False, "protected": protected.report(), "verification": args.verify}
    try:
        script = output / "fixture.lua"
        script.write_text(
            f"_IsaacLanProjectileFixture = {{ verify = {str(args.verify).lower()} }}\n"
            + (ROOT / "tests/state_projectile_pressure.lua").read_text()
        )
        command = engine_command(
            labs,
            args.build,
            output / "engine",
            script,
            "LAN_NETWORK PASS projectile pressure",
            "--frontend",
            "--no-luadebug",
            "--menu-start",
            "--virtual-input",
            "--automatic",
            "--menu-port",
            str(args.port),
            "--latency-ms",
            str(args.latency_ms),
            "--scenario-timeout",
            "300",
        )
        if args.phase_profile:
            command.append("--performance")
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
        report["measurements"] = {}
        for role in ("host", "client"):
            path = output / "engine" / role / "log.txt"
            if path.is_file():
                report["measurements"][role] = [
                    json.loads(line.split("LAN_PROJECTILE_PRESSURE ", 1)[1])
                    for line in path.read_text(errors="replace").splitlines()
                    if "LAN_PROJECTILE_PRESSURE {" in line
                ]
        idle(labs, exclusive=not args.verify)
    finally:
        finish_run(protected, report, output)
    print(json.dumps({"passed": report["passed"], "restored": report["restored"]}))
    return 0 if report["passed"] and report["restored"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
