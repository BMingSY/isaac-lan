#!/usr/bin/env python3
"""Run an owned Boss shard, record both peers, and restore all isolated saves."""

import argparse
from testing.bosses import evidence
import json
from pathlib import Path
import shutil
import subprocess

from testing.bosses import build, scenario_timeout
from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command, run_engine
from lab_profile import validate_labs as validate_owned_labs
from lab_profile import ProtectedLabs, idle

ROOT = Path(__file__).resolve().parents[1]
from testing.bosses import COMPLETION


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30600)
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shards", type=int, default=1)
    parser.add_argument("--case", action="append")
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    labs = validate_owned_labs(
        [args.host.resolve(), args.client.resolve()], args.output.resolve(), count=None
    )
    output = args.output.resolve()
    idle(labs)
    output.mkdir(parents=True, exist_ok=False)
    script = output / "bosses.lua"
    cases = build(script, args.shard, args.shards, args.case)
    subprocess.run([shutil.which("luac5.3") or "luac", "-p", str(script)], check=True)
    protected = ProtectedLabs(labs, output, roles=("host", "client"))
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        COMPLETION,
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--endings-fixture",
        "--native-record-both",
        "--frame-ms",
        "1000",
        "--latency-ms",
        "20",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        str(scenario_timeout(len(cases))),
    )
    if args.heap_check:
        command.append("--heap-check")
    report = {
        "passed": False,
        "restored": False,
        "shard": args.shard,
        "shards": args.shards,
        "cases": cases,
        "command": command,
    }
    try:
        with (output / "engine.log").open("w") as log:
            result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        report["peers"] = {}
        for role in ("host", "client"):
            path = output / "engine" / role / "log.txt"
            report["peers"][role] = evidence(
                path.read_text(errors="replace") if path.exists() else "", cases
            )
        report["passed"] = result.returncode == 0 and all(
            peer["passed"] for peer in report["peers"].values()
        )
    finally:
        finish_run(protected, report, output)
    print(json.dumps({key: report[key] for key in ("passed", "restored")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
