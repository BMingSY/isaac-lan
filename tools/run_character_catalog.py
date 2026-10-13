#!/usr/bin/env python3
"""Validate native Mod character selection in four idle owned labs.

The three sessions share one group of processes. This runner refuses the user's
host-001/client-001 labs and preserves each selected lab's profile and saves.
"""

import argparse
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

from progress_fixture import MAGIC, checksum
from run_endings import hashes, idle
from run_network_engine import log_path, windows

ROOT = Path(__file__).resolve().parents[1]
ROLES = ("host", "client", "client2", "client3")
COMPLETION = "LAN_NETWORK PASS native character catalog"


def validate_labs(labs):
    resolved = [Path(lab).resolve() for lab in labs]
    if len(resolved) != 4 or len(set(resolved)) != 4:
        raise ValueError("Four distinct owned labs are required")
    if any(lab.name.casefold() in {"host-001", "client-001"} for lab in resolved):
        raise ValueError("host-001/client-001 are reserved for the user's manual games")
    if any(not (lab / ".isaac-lan-lab").is_file() for lab in resolved):
        raise ValueError("Every selected lab needs an .isaac-lan-lab ownership marker")
    if any(not (lab / "game/isaac-ng.exe").is_file() for lab in resolved):
        raise ValueError("Every selected lab needs its own game executable")
    return resolved


def progress_evidence(source):
    if not 2800 <= len(source) <= 4 * 1024 * 1024 or source[:16] != MAGIC:
        raise ValueError("A native J460 progress baseline is required")
    if struct.unpack_from("<I", source, len(source) - 4)[0] != checksum(source[16:-4]):
        raise ValueError("Native progress baseline checksum differs")
    if struct.unpack_from("<3I", source, 20) != (1, 642, 642):
        raise ValueError("Unsupported native achievement section")
    flags = source[32:674]
    if any(flag > 1 for flag in flags):
        raise ValueError("Invalid native achievement flags")
    if flags[475]:
        raise ValueError("This fixture requires achievement 475 locked before startup")
    if flags[477]:
        raise ValueError("This fixture requires Tainted Magdalene (477) locked before startup")
    return {
        "achievement_475": False,
        "tainted_magdalene_477": False,
        "unlocked_achievements": sum(flags),
    }


def peer_evidence(text, ordinal):
    cases = ("two-normal", "three-mixed", "four-tainted")
    participated = [case for players, case in zip((2, 3, 4), cases) if ordinal < players]
    required = [COMPLETION, "REGISTERED ids="]
    for case in participated:
        prefix = "CHARACTER_CATALOG case=" + case + " "
        required += [prefix + "MENU_SELECTED ", prefix + "PASS menu_cleanup=true"]
        required += [prefix + ("FINAL_TYPES " if ordinal == 0 else "REPLICA_TYPES_VERIFIED ")]
    return {
        "passed": all(marker in text for marker in required) and "LAN_NETWORK FAILED" not in text,
        "cases": participated,
        "missing": [marker for marker in required if marker not in text],
        "evidence": [line for line in text.splitlines() if "CHARACTER_CATALOG " in line],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--extra-client", type=Path, action="append", default=[])
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30420)
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--frame-ms", type=int, default=500)
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    try:
        labs = validate_labs([args.host, args.client, *args.extra_client])
    except ValueError as error:
        parser.error(str(error))
    if not 1 <= args.port < 65535 or not 16 <= args.frame_ms <= 1000:
        parser.error("Invalid port or frame interval")
    output = args.output.resolve()
    if any(output.is_relative_to(lab) or lab.is_relative_to(output) for lab in labs):
        parser.error("The evidence directory must be separate from all selected labs")
    initial = {
        role: progress_evidence((log_path(lab).parent / "persistentgamedata1.dat").read_bytes())
        for role, lab in zip(ROLES, labs)
    }
    # Read-only process check; never stop or replace an existing game.
    idle(labs)
    output.mkdir(parents=True, exist_ok=False)
    coordination = output / "coordination"
    coordination.mkdir()
    (coordination / "case.txt").write_text("1")
    script = output / "suite.lua"
    script.write_text(
        "local characterCoordination = "
        + json.dumps(windows(coordination).replace("\\", "/"))
        + "\n"
        + (ROOT / "tests/state_character_catalog.lua").read_text()
    )
    protected = []
    for role, lab in zip(ROLES, labs):
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
        "--extra-client",
        str(labs[2]),
        "--extra-client",
        str(labs[3]),
        "--build",
        str(args.build.resolve()),
        "--output",
        str(output / "engine"),
        "--script",
        str(script),
        "--completion",
        COMPLETION,
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "600",
        "--mod",
        str(ROOT / "tests/fixtures/registered_characters"),
    ]
    if args.record:
        command += ["--native-record-both", "--frame-ms", str(args.frame_ms)]
    if args.heap_check:
        command.append("--heap-check")
    report = {
        "passed": False,
        "restored": False,
        "command": command,
        "initial_progress": initial,
        "progress_mutation": False,
        "peers": {},
        "visual_review_required": args.record,
    }
    try:
        for lab in labs:
            options = log_path(lab).parent / "options.ini"
            options.write_text(re.sub(r"(?m)^PopUps=.*$", "PopUps=0", options.read_text()))
        with (output / "engine.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        for ordinal, role in enumerate(ROLES):
            log = output / "engine" / role / "log.txt"
            text = log.read_text(errors="replace") if log.exists() else ""
            report["peers"][role] = peer_evidence(text, ordinal)
        report["passed"] = result.returncode == 0 and all(
            peer["passed"] for peer in report["peers"].values()
        )
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
    print(json.dumps({key: report[key] for key in ("passed", "restored")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
