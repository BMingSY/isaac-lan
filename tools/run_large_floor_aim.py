#!/usr/bin/env python3
"""Validate large floors and fixed-seat aiming with one owned group of game processes."""

import argparse
import configparser
from pathlib import Path
import subprocess

from game_logs import log_path
from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup, windows
from testing.engine import configure_interrupts, engine_command, run_engine
from testing.lua import literal
from testing.profiles import profile_fixture
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--extra-client", type=Path, action="append", default=[])
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=31840)
    parser.add_argument("--challenge", type=int, choices=(1004, 1005))
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--record", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("Invalid port")
    labs = validate_labs([args.host, args.client, *args.extra_client], args.output, count=None)
    idle(labs)
    validate_startup(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    shared = output / "coordination"
    shared.mkdir()
    (shared / "case.txt").write_text("1")
    script = output / "suite.lua"
    script.write_text(
        "local challengeCoordination = "
        + literal(windows(shared).replace("\\", "/"))
        + "\nlocal challengeMaxPlayers = "
        + str(len(labs))
        + "\nlocal challengeFilter = "
        + (str(args.challenge) if args.challenge else "nil")
        + "\n"
        + (ROOT / "tests/state_large_floor_aim.lua").read_text()
    )
    roles = ["host", "client", "client2", "client3"][: len(labs)]
    protected = ProtectedLabs(labs, output, roles=roles)
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        "LAN_NETWORK PASS large floor and aiming challenges",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "900",
    )
    for lab in labs[2:]:
        command.extend(("--extra-client", str(lab)))
    if args.heap_check:
        command.append("--heap-check")
    if args.record:
        command.extend(("--native-record-both", "--frame-ms", "1000"))
    report = {"passed": False, "command": command, "protected": protected.report()}
    try:
        for lab in labs:
            profile = log_path(lab).parent / "persistentgamedata1.dat"
            profile.write_bytes(profile_fixture(profile.read_bytes()))
            options = profile.parent / "options.ini"
            settings = configparser.ConfigParser()
            settings.optionxform = str
            settings.read(options)
            settings["Options"]["MouseControl"] = "1"
            settings["Options"]["PopUps"] = "0"
            with options.open("w") as stream:
                settings.write(stream)
        with (output / "engine.log").open("w") as log:
            report["returncode"] = run_engine(
                command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT
            ).returncode
        report["passed"] = report["returncode"] == 0
    finally:
        finish_run(protected, report, output)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
