#!/usr/bin/env python3
"""Run native Home/hourglass sessions in one group of four idle owned labs.

Normal and Hard cover real R Key/Home, host rewind and guest rewind. Profiles,
native saves and LAN archives are restored byte for byte after owned processes
exit. The user's host-001/client-001 labs are always rejected.
By default all nine sessions run; --players narrows a later targeted rerun.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

from lab_profile import ProtectedLabs, idle
from game_logs import log_path
from lab_profile import windows

ROOT = Path(__file__).resolve().parents[1]
ROLES = ("host", "client", "client2", "client3")
COMPLETION = "LAN_NETWORK PASS native Home hourglass team"
CASES = tuple(
    (players, f"{kind}-{players}")
    for players in (2, 3, 4)
    for kind in ("home", "rewind-host", "rewind-guest")
)


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
    if any(not (log_path(lab).parent / "options.ini").is_file() for lab in resolved):
        raise ValueError("Every selected lab needs an existing isolated options.ini")
    return resolved


def peer_evidence(text, ordinal, groups=(2, 3, 4)):
    participated = [
        (players, case) for players, case in CASES if players in groups and ordinal < players
    ]
    required = [COMPLETION]
    for players, case in participated:
        prefix = "HOURGLASS_HOME case=" + case + " "
        required.append(prefix + "PASS home_events=")
        if ordinal == 0:
            required += [prefix + "TRANSITION_PASS ", prefix + "SPLIT_PASS "]
            required += [prefix + f"WALK_PASS slot={slot} " for slot in range(players)]
            if case == "home-2":
                required.append(prefix + "FRESH_START_PASS ")
            elif case.startswith("home-"):
                required.append(prefix + "R_KEY_PASS ")
        else:
            required += [prefix + "REPLICA_ARRIVED ", prefix + "FLOOR_EVENT "]
    if ordinal == 0 and 4 in groups:
        required.append("HOURGLASS_HOME case=home-4 HOME_REJOIN_PASS ")
    if ordinal == 3 and 4 in groups:
        required.append("HOURGLASS_HOME case=home-4 HOME_REJOIN_RESTORED ")
    return {
        "passed": all(marker in text for marker in required) and "LAN_NETWORK FAILED" not in text,
        "cases": [case for _, case in participated],
        "missing": [marker for marker in required if marker not in text],
        "evidence": [line for line in text.splitlines() if "HOURGLASS_HOME " in line],
    }


def transition_evidence(probe, ordinal, players=(2, 3, 4)):
    counts = {
        "floor_sent": probe.count("floor_event=SENT "),
        "floor_received": probe.count("floor_event=RECEIVED "),
        "rewind_sent": probe.count("hourglass_event=SENT "),
        "r_key": probe.count("floor_transaction=R_KEY"),
    }
    groups = sum(ordinal < count for count in players)
    restarts = sum(ordinal < count for count in players if count != 2)
    expected = {
        "floor_sent": groups + restarts if ordinal == 0 else 0,
        "floor_received": 0 if ordinal == 0 else groups * 3 + restarts,
        "rewind_sent": groups * 2 if ordinal == 0 else 0,
        "r_key": restarts,
    }
    return {"passed": counts == expected, "actual": counts, "expected": expected}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--extra-client", type=Path, action="append", default=[])
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30460)
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--frame-ms", type=int, default=500)
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--players", type=int, choices=(2, 3, 4), nargs="+", default=[2, 3, 4])
    args = parser.parse_args()
    selected_players = sorted(set(args.players))
    try:
        labs = validate_labs([args.host, args.client, *args.extra_client])
    except ValueError as error:
        parser.error(str(error))
    if not 1 <= args.port < 65535 or not 16 <= args.frame_ms <= 1000:
        parser.error("Invalid port or frame interval")
    output = args.output.resolve()
    if any(output.is_relative_to(lab) or lab.is_relative_to(output) for lab in labs):
        parser.error("The evidence directory must be separate from all selected labs")
    # Read-only process check: only the shared runner may operate its new PIDs.
    idle(labs)
    output.mkdir(parents=True, exist_ok=False)
    coordination = output / "coordination"
    coordination.mkdir()
    (coordination / "case.txt").write_text("1")
    script = output / "suite.lua"
    script.write_text(
        "local hourglassPlayers = {"
        + ",".join(map(str, selected_players))
        + "}\nlocal hourglassCoordination = "
        + json.dumps(windows(coordination).replace("\\", "/"))
        + "\n"
        + (ROOT / "tests/state_hourglass_home.lua").read_text()
    )
    protected = ProtectedLabs(labs, output, roles=ROLES)
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
        "1800",
    ]
    if args.record:
        command += ["--native-record-both", "--frame-ms", str(args.frame_ms)]
    if args.heap_check:
        command.append("--heap-check")
    report = {
        "passed": False,
        "restored": False,
        "command": command,
        "cases": [case for players, case in CASES if players in selected_players],
        "difficulty": {"two": "normal", "three": "hard", "four": "normal"},
        "progress_mutation": False,
        "peers": {},
        "visual_review_required": args.record,
        "not_covered": ["Greed", "console rewind", "ordinary cross-floor rewind"],
        "protected": protected.report(),
    }
    try:
        for lab in labs:
            options = log_path(lab).parent / "options.ini"
            options.write_text(re.sub(r"(?m)^PopUps=.*$", "PopUps=0", options.read_text()))
        with (output / "engine.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        report["returncode"] = result.returncode
        for ordinal, role in enumerate(ROLES):
            directory = output / "engine" / role
            log, probe = directory / "log.txt", directory / "probe.log"
            peer = peer_evidence(
                log.read_text(errors="replace") if log.exists() else "", ordinal, selected_players
            )
            peer["transitions"] = transition_evidence(
                probe.read_text(errors="replace") if probe.exists() else "",
                ordinal,
                selected_players,
            )
            peer["passed"] &= peer["transitions"]["passed"]
            report["peers"][role] = peer
        report["passed"] = result.returncode == 0 and all(
            peer["passed"] for peer in report["peers"].values()
        )
    finally:
        try:
            for source, actual in protected.restore().items():
                report["protected"][source]["after"] = actual
            report["restored"] = True
        except Exception as error:
            report["restoration_error"], report["passed"] = str(error), False
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ("passed", "restored")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
