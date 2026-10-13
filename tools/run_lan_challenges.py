#!/usr/bin/env python3
"""Validate LAN challenges in one protected group of two to four native processes.

This fixture uses lab-only Lua debug mode for file coordination and bytewise
archive checks. It does not change the production Lua sandbox.
"""

import argparse
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

from run_endings import hashes, idle
from run_network_engine import log_path, windows
from progress_fixture import MAGIC, checksum

ROOT = Path(__file__).resolve().parents[1]


def profile_fixture(source, *, negative=True, tainted_cain=True):
    """Prepare startup-only qualification while preserving every unrelated byte."""
    if not 2800 <= len(source) <= 4 * 1024 * 1024 or source[:16] != MAGIC:
        raise ValueError("A native J460 progress baseline is required")
    if struct.unpack_from("<I", source, len(source) - 4)[0] != checksum(source[16:-4]):
        raise ValueError("Native progress baseline checksum differs")
    if struct.unpack_from("<3I", source, 20) != (1, 642, 642):
        raise ValueError("Unsupported native achievement section")
    if struct.unpack_from("<3I", source, 674) != (2, 523 * 4, 523):
        raise ValueError("Unsupported native counter section")
    if any(value > 1 for value in source[32:674]):
        raise ValueError("Invalid native achievement flags")
    data = bytearray(source)
    for identifier, unlocked in ((4, True), (34, True), (78, negative), (476, tainted_cain)):
        data[32 + identifier] = int(unlocked)
    struct.pack_into("<I", data, len(data) - 4, checksum(data[16:-4]))
    return bytes(data)


def completion_evidence(probe, *, ordinal, players, expected=None):
    """A trophy must broadcast FinishChallenge, rather than a normal ending."""
    lines = [line for line in probe.splitlines() if "ending_event=" in line]
    events = []
    for line in lines:
        match = re.search(r"ending_event=(SENT|RECEIVED) id=(\d+) completed=([01])\b", line)
        if match:
            events.append(
                {
                    "direction": match[1],
                    "id": int(match[2]),
                    "completed": match[3] == "1",
                }
            )
    if expected is None:
        expected = players - max(2, ordinal + 1) + 1
    direction = "SENT" if ordinal == 0 else "RECEIVED"
    return {
        "events": events,
        "expected": expected,
        "passed": len(events) == len(lines) == expected
        and all(event["completed"] and event["direction"] == direction for event in events),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--extra-client", type=Path, action="append", default=[])
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mod", type=Path, action="append", default=[])
    parser.add_argument("--port", type=int, default=30320)
    parser.add_argument("--latency-ms", type=int, default=0)
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--frame-ms", type=int, default=500)
    parser.add_argument(
        "--suite",
        choices=("access", "gameplay", "hud"),
        default="gameplay",
        help="Access checks startup qualifications; gameplay checks completion; hud checks views and cleanup",
    )
    parser.add_argument(
        "--hourglass-shared-room",
        action="store_true",
        help="Run the shared-room control; excludes the split starting-room/Home boundary",
    )
    args = parser.parse_args()
    labs = [args.host.resolve(), args.client.resolve(), *(p.resolve() for p in args.extra_client)]
    if not 2 <= len(labs) <= 4 or len(set(labs)) != len(labs):
        parser.error("Two to four distinct labs are required")
    if args.suite == "access" and len(labs) != 4:
        parser.error("The access suite requires four distinct startup profiles")
    if args.suite == "access" and args.latency_ms:
        parser.error("The access suite rotates hosts and requires --latency-ms 0")
    if any(not (lab / ".isaac-lan-lab").is_file() for lab in labs):
        parser.error("Every lab must have an .isaac-lan-lab ownership marker")
    if not 1 <= args.port < 65535 or not 0 <= args.latency_ms <= 1000:
        parser.error("Invalid port or latency")
    if not 16 <= args.frame_ms <= 1000:
        parser.error("Frame interval must be 16..1000 ms")
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    shared = output / "coordination"
    shared.mkdir()
    (shared / "case.txt").write_text("1")
    script = output / "suite.lua"
    fixture = (
        ROOT
        / "tests"
        / (
            "state_lan_challenge_access.lua"
            if args.suite == "access"
            else "state_lan_challenges.lua"
        )
    )
    if not fixture.is_file():
        parser.error("The requested suite fixture does not exist")
    script.write_text(
        "local challengeCoordination = "
        + json.dumps(windows(shared).replace("\\", "/"))
        + "\nlocal challengeMaxPlayers = "
        + str(len(labs))
        + "\nlocal challengeRequireEid = "
        + ("true" if args.mod else "false")
        + "\nlocal challengeHourglassSharedRoom = "
        + ("true" if args.hourglass_shared_room else "false")
        + "\nlocal challengeHudOnly = "
        + ("true" if args.suite == "hud" else "false")
        + "\n"
        + fixture.read_text()
    )
    roles = ["host", "client", "client2", "client3"][: len(labs)]
    protected = []
    for role, lab in zip(roles, labs):
        for folder in ("profile", "game/data", "game/isaac-lan"):
            source = lab / folder
            backup = output / "before" / role / folder
            protected.append((source, backup, hashes(source), source.exists()))
            if source.exists():
                shutil.copytree(source, backup)
    command = [
        sys.executable,
        str(ROOT / "tools/run_network_engine.py"),
        "--host",
        str(labs[0]),
        "--client",
        str(labs[1]),
        "--build",
        str(args.build.resolve()),
        "--output",
        str(output / "engine"),
        "--script",
        str(script),
        "--completion",
        "LAN_NETWORK PASS concentrated LAN challenges",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--menu-port",
        str(args.port),
        "--latency-ms",
        str(args.latency_ms),
        "--scenario-timeout",
        "1800",
    ]
    for lab in labs[2:]:
        command += ["--extra-client", str(lab)]
    for mod in args.mod:
        command += ["--mod", str(mod.resolve())]
    if args.record:
        command += ["--native-record-both", "--frame-ms", str(args.frame_ms)]
    if args.heap_check:
        command.append("--heap-check")
    report = {
        "passed": False,
        "restored": False,
        "command": command,
        "peers": {},
        "initial_progress": {},
        "fixture_progress": {},
        "suite": args.suite,
        "startup_profiles_required": True,
        "hourglass_mode": ("shared-room-control" if args.hourglass_shared_room else "split-room")
        if args.suite == "gameplay"
        else None,
        "hourglass_excluded_boundary": (
            "Host remains in first-visit starting room while guest rewinds"
            if args.suite == "gameplay" and args.hourglass_shared_room
            else None
        ),
    }
    prepared_profiles = []
    for index, (role, lab) in enumerate(zip(roles, labs)):
        progress = (log_path(lab).parent / "persistentgamedata1.dat").read_bytes()
        if progress[:16] != b"ISAACNGSAVE09R  " or len(progress) < 674:
            raise ValueError("Expected a native J460 progress baseline")
        flags = progress[32:674]
        if args.suite == "access" and flags[475]:
            raise ValueError("Access fixture requires a baseline with Tainted Magdalene locked")
        report["initial_progress"][role] = {
            "unlocked_achievements": sum(flags),
            "womb_unlocked": bool(flags[4]),
            "negative_unlocked": bool(flags[78]),
            "tainted_cain_unlocked": bool(flags[476]),
        }
        negative = args.suite != "access" or index not in (1, 3)
        tainted_cain = args.suite != "access" or index not in (2, 3)
        prepared_profiles.append(
            profile_fixture(progress, negative=negative, tainted_cain=tainted_cain)
        )
        report["fixture_progress"][role] = {
            "negative_unlocked": negative,
            "tainted_cain_unlocked": tainted_cain,
            "only_changed_achievement_ids": [4, 34, 78, 476],
        }
    try:
        for lab, progress in zip(labs, prepared_profiles):
            # Native character-menu counts are cached at startup. Never patch
            # unlocks in a running process; the finally block restores the file.
            profile = log_path(lab).parent / "persistentgamedata1.dat"
            with tempfile.NamedTemporaryFile(
                dir=profile.parent, prefix=".lan-challenge-", delete=False
            ) as temporary:
                temporary.write(progress)
                prepared = Path(temporary.name)
            try:
                prepared.replace(profile)
            finally:
                prepared.unlink(missing_ok=True)
            options = log_path(lab).parent / "options.ini"
            text = options.read_text()
            text = re.sub(r"(?m)^PopUps=.*$", "PopUps=0", text)
            options.write_text(text)
        with (output / "engine.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        for ordinal, role in enumerate(roles):
            log = output / "engine" / role / "log.txt"
            text = log.read_text(errors="replace") if log.exists() else ""
            report["peers"][role] = {
                "passed": "LAN_NETWORK PASS concentrated LAN challenges" in text,
                "evidence": [line for line in text.splitlines() if "LAN_CHALLENGE " in line],
            }
            if args.suite in ("gameplay", "hud"):
                probe = output / "engine" / role / "probe.log"
                completion = completion_evidence(
                    probe.read_text(errors="replace") if probe.exists() else "",
                    ordinal=ordinal,
                    players=len(labs),
                    expected=0 if args.suite == "hud" else None,
                )
                report["peers"][role]["challenge_completion"] = completion
                report["peers"][role]["passed"] &= completion["passed"]
        report["passed"] = result.returncode == 0 and all(
            p["passed"] for p in report["peers"].values()
        )
        report["visual_review_required"] = bool(args.record)
    finally:
        try:
            idle(labs)
            for source, backup, baseline, existed in protected:
                if source.exists():
                    shutil.rmtree(source)
                if existed:
                    shutil.copytree(backup, source)
                assert hashes(source) == baseline, "Protected lab files differ after restoration"
            report["restored"] = True
        except Exception as error:
            report["restoration_error"], report["passed"] = str(error), False
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
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
