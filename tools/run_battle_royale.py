#!/usr/bin/env python3
"""Validate challenge 1003 in one protected native host/client session."""

import argparse
from pathlib import Path

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
    parser.add_argument("--port", type=int, default=30803)
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--case", choices=("full", "flow"), default="full")
    parser.add_argument("--winner", choices=("host", "client"), default="host")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("--port must be between 1024 and 65535")
    labs = validate_labs([args.host, args.client], args.output)
    idle(labs)
    validate_startup(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output)
    fixture = output / "suite.lua"
    fixture.write_text(
        f"_IsaacLanBattleFlow = {str(args.case == 'flow').lower()}\n"
        f"_IsaacLanBattleWinner = {0 if args.winner == 'host' else 1}\n"
        + (ROOT / "tests/state_battle_royale.lua").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        fixture,
        "LAN_NETWORK PASS battle royale",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "720",
    )
    if args.heap_check:
        command.append("--heap-check")
    if args.record:
        command.extend(("--native-record-both", "--frame-ms", "1000"))
    report = {"passed": False, "command": command, "protected": protected.report()}
    try:
        report["returncode"] = run_engine(command).returncode
        report["passed"] = report["returncode"] == 0
    finally:
        finish_run(protected, report, output)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
