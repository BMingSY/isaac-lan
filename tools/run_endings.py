#!/usr/bin/env python3
"""Run six ending routes with one isolated pair and restore its test saves."""

import argparse
from testing.endings import route_evidence
import json
from pathlib import Path
import subprocess

from testing.endings import CASES, build
from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command, run_engine
from lab_profile import validate_labs as validate_owned_labs
from lab_profile import ProtectedLabs, idle

ROOT = Path(__file__).resolve().parents[1]


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mod", type=Path, action="append", default=[])
    parser.add_argument("--port", type=int, default=30120)
    parser.add_argument("--first-floor", action="store_true")
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument(
        "--route",
        choices=CASES,
        action="append",
        help="Run selected routes when diagnosing a failure; default: all six",
    )
    args = parser.parse_args()
    cases = args.route or CASES
    if len(set(cases)) != len(cases):
        parser.error("Each selected route must appear once")
    labs = validate_owned_labs(
        [args.host.resolve(), args.client.resolve()], args.output.resolve(), count=None
    )
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script = output / "suite.lua"
    build(script, args.route, first_floor=args.first_floor)
    protected = ProtectedLabs(labs, output, roles=("host", "client"))
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        "LAN_NETWORK PASS all selected native ending routes",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--no-luadebug",
        "--automatic",
        "--endings-fixture",
        "--native-record-both",
        "--frame-ms",
        "500",
        "--latency-ms",
        "75",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "1800",
    )
    if args.heap_check:
        command.append("--heap-check")
    for mod in args.mod:
        command += ["--mod", str(mod.resolve())]
    report = {"passed": False, "restored": False, "routes": {}, "command": command}
    try:
        with (output / "engine.log").open("w") as log:
            result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        for name in cases:
            peers = {}
            for role in ("host", "client"):
                path = output / "engine" / role / "log.txt"
                text = path.read_text(errors="replace") if path.exists() else ""
                peers[role] = route_evidence(text, name)
            report["routes"][name] = peers
        report["passed"] = result.returncode == 0 and all(
            peer["win"]
            and peer["cleanup"]
            and peer["progress"]
            and not peer["missing_alternate_floors"]
            for peers in report["routes"].values()
            for peer in peers.values()
        )
    finally:
        # Do not restore files beneath a surviving process, including if a
        # native crash prevented the runner from completing owned cleanup.
        finish_run(protected, report, output)
    print(
        json.dumps(
            {
                "passed": report["passed"],
                "restored": report["restored"],
                "report": str(output / "report.json"),
            },
            indent=2,
        )
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
