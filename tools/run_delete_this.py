#!/usr/bin/env python3
"""Play LAN challenge 45 from the first floor with a protected pair of LANBOTs."""

import argparse
import json
from pathlib import Path
import struct
import subprocess

from game_logs import log_path
from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup
from progress_fixture import checksum, MAGDALENE_ACHIEVEMENT, AZAZEL_ACHIEVEMENT, AZAZEL_PLAYER_TYPE
from testing.challenges import completion_evidence
from testing.engine import configure_interrupts, engine_command, run_engine
from testing.lua import factory, write_suite
from testing.profiles import profile_fixture
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]
COMPLETION = "LAN_NETWORK PASS all selected character and side routes"
CASE_COMPLETION = (
    "LAN_NETWORK CHALLENGE45 PASS completion, synchronization and personal progress restoration"
)


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--progress-template", type=Path)
    parser.add_argument("--seed", default="YV039KQF")
    parser.add_argument("--mode", choices=("natural", "route"), default="natural")
    parser.add_argument(
        "--then-natural",
        action="store_true",
        help="Reuse the same processes for an unassisted double-Azazel run after route mode",
    )
    parser.add_argument(
        "--characters", type=int, nargs=2, choices=(0, 1, AZAZEL_PLAYER_TYPE), default=[0, 1]
    )
    parser.add_argument(
        "--style", choices=("balanced", "aggressive", "cautious"), default="balanced"
    )
    parser.add_argument("--port", type=int, default=52971)
    parser.add_argument("--latency-ms", type=int, default=40)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--record", action="store_true")
    args = parser.parse_args()
    if args.then_natural and args.mode != "route":
        parser.error("--then-natural requires --mode route")
    labs = validate_labs([args.host, args.client], args.output)
    idle(labs)
    validate_startup(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script = output / "scenario.lua"
    scenarios = [
        {
            "seed": args.seed,
            "mode": args.mode,
            "characters": args.characters,
            "style": args.style,
        }
    ]
    if args.then_natural:
        scenarios.append(
            {
                "seed": "LBCD0G4M",
                "mode": "natural",
                "characters": [AZAZEL_PLAYER_TYPE, AZAZEL_PLAYER_TYPE],
                "style": "aggressive",
            }
        )
    write_suite(
        script,
        [factory("state_delete_this.lua", options={"deleteThis": case}) for case in scenarios],
    )
    template = args.progress_template or log_path(labs[0]).parent / "persistentgamedata1.dat"
    profile = bytearray(profile_fixture(template.read_bytes()))
    # Use an otherwise locked native profile to exercise original-challenge
    # route access independently of ordinary Womb/Polaroid unlocks.
    achievements_start, achievement_count, counters_start, counter_count = 32, 642, 686, 523
    profile[achievements_start : achievements_start + achievement_count] = bytes(achievement_count)
    qualifications = [
        achievement
        for character, achievement in (
            (1, MAGDALENE_ACHIEVEMENT),
            (AZAZEL_PLAYER_TYPE, AZAZEL_ACHIEVEMENT),
        )
        if any(character in case["characters"] for case in scenarios)
    ]
    for achievement in qualifications:
        profile[achievements_start + achievement] = 1
    profile[counters_start : counters_start + counter_count * 4] = bytes(counter_count * 4)
    struct.pack_into("<I", profile, len(profile) - 4, checksum(profile[16:-4]))
    protected = ProtectedLabs(labs, output)
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        COMPLETION,
        "--frontend",
        "--automatic",
        "--menu-start",
        "--virtual-input",
        "--menu-port",
        str(args.port),
        "--latency-ms",
        str(args.latency_ms),
        "--scenario-timeout",
        str(args.timeout),
    )
    if args.heap_check:
        command.append("--heap-check")
    if args.record:
        command.extend(("--native-record-both", "--frame-ms", "1000"))
    report = {
        "passed": False,
        "mode": args.mode,
        "seed": args.seed,
        "characters": args.characters,
        "style": args.style,
        "scenarios": scenarios,
        "command": command,
        "assistance": []
        if args.mode == "natural"
        else [
            "keep players in generated Boss rooms",
            "restore soul hearts",
            "Spoon Bender",
            "minimum player tear damage 50",
            "public LANBOT next command after Boss reward",
        ],
        "startup_achievements": qualifications,
    }
    try:
        for lab in labs:
            (log_path(lab).parent / "persistentgamedata1.dat").write_bytes(profile)
        with (output / "engine.log").open("w") as log:
            result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        report["returncode"] = result.returncode
        engine_report = json.loads((output / "engine" / "result.json").read_text())
        if result.returncode != 0:
            report["error"] = engine_report.get("error", "Native challenge run did not complete")
        report["peers"] = {}
        for ordinal, role in enumerate(("host", "client")):
            folder = output / "engine" / role
            probe = (
                (folder / "probe.log").read_text(errors="replace")
                if (folder / "probe.log").exists()
                else ""
            )
            log = (
                (folder / "log.txt").read_text(errors="replace")
                if (folder / "log.txt").exists()
                else ""
            )
            report["peers"][role] = {
                "completed": COMPLETION in log,
                "completed_cases": log.count(CASE_COMPLETION),
                "completion": completion_evidence(
                    probe, ordinal=ordinal, players=2, expected=len(scenarios)
                ),
                "evidence": [line for line in log.splitlines() if "CHALLENGE45 " in line],
            }
        report["passed"] = result.returncode == 0 and all(
            p["completed"] and p["completed_cases"] == len(scenarios) and p["completion"]["passed"]
            for p in report["peers"].values()
        )
    finally:
        finish_run(protected, report, output)
    print(json.dumps({k: report.get(k) for k in ("passed", "restored", "error")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
