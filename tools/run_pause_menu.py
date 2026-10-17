#!/usr/bin/env python3
"""Exercise native pause submenus and lifecycle with one protected idle pair.

Only the selected owned labs may be launched. The user's host-001/client-001
manual games are always refused. All profile and LAN-save bytes are restored.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from testing.profiles import magdalene_profile
from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command, run_engine
from lab_profile import validate_labs as validate_owned_labs
from lab_profile import ProtectedLabs, idle
from game_logs import log_path
from lab_profile import windows

ROOT = Path(__file__).resolve().parents[1]
from testing.pause import COMPLETION, peer_evidence


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30440)
    parser.add_argument(
        "--pause-pulses", type=int, default=8, help="Even number of one-frame Start presses (2..32)"
    )
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--frame-ms", type=int, default=500)
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--eid-feedback", type=Path, help="Also check EID and guest focus loss")
    args = parser.parse_args()
    labs = validate_owned_labs(
        [args.host.resolve(), args.client.resolve()], args.output.resolve(), count=None
    )
    if not 2 <= args.pause_pulses <= 32 or args.pause_pulses % 2:
        parser.error("--pause-pulses must be an even integer from 2 to 32")
    if not 1 <= args.port < 65535 or not 16 <= args.frame_ms <= 1000:
        parser.error("Invalid port or frame interval")
    output = args.output.resolve()
    idle(labs)
    source_progress = (log_path(labs[1]).parent / "persistentgamedata1.dat").read_bytes()
    prepared_progress = magdalene_profile(source_progress)
    output.mkdir(parents=True, exist_ok=False)
    coordination = output / "coordination"
    coordination.mkdir()
    (coordination / "step.txt").write_text("1")
    script = output / "suite.lua"
    script.write_text(
        "local pauseCoordination = "
        + json.dumps(windows(coordination).replace("\\", "/"))
        + "\nlocal pausePulses = "
        + str(args.pause_pulses)
        + "\nlocal pauseFeedback = "
        + ("true" if args.eid_feedback else "false")
        + "\n"
        + (ROOT / "tests/state_pause_menu.lua").read_text()
    )
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
        "--keyboard-pause",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "600",
    )
    if args.record:
        command += ["--native-record-both", "--frame-ms", str(args.frame_ms)]
    if args.heap_check:
        command.append("--heap-check")
    if args.eid_feedback:
        command += ["--mod", str(args.eid_feedback.resolve()), "--focus-cycle"]
    report = {
        "passed": False,
        "restored": False,
        "command": command,
        "pause_pulses": args.pause_pulses,
        "fixture_progress": {"client_achievement_1": True, "changed_achievement_ids": [1]},
        "peers": {},
        "visual_review_required": args.record,
    }
    try:
        profile = log_path(labs[1]).parent / "persistentgamedata1.dat"
        with tempfile.NamedTemporaryFile(
            dir=profile.parent, prefix=".pause-menu-", delete=False
        ) as temp:
            temp.write(prepared_progress)
            prepared = Path(temp.name)
        try:
            prepared.replace(profile)
        finally:
            prepared.unlink(missing_ok=True)
        for lab in labs:
            options = log_path(lab).parent / "options.ini"
            options.write_text(re.sub(r"(?m)^PopUps=.*$", "PopUps=0", options.read_text()))
        with (output / "engine.log").open("w") as log:
            result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        for role in ("host", "client"):
            log = output / "engine" / role / "log.txt"
            text = log.read_text(errors="replace") if log.exists() else ""
            report["peers"][role] = peer_evidence(text, role == "host", args.pause_pulses)
            if args.eid_feedback:
                feedback = all(
                    marker in text
                    for marker in ("EID_STABLE samples=180", "step=guest-focus-loss CHECK ")
                )
                report["peers"][role]["eid_focus_feedback"] = feedback
                report["peers"][role]["passed"] &= feedback
        report["passed"] = result.returncode == 0 and all(
            peer["passed"] for peer in report["peers"].values()
        )
        if args.eid_feedback:
            engine = json.loads((output / "engine" / "result.json").read_text())
            report["focus_cycles"] = engine.get("focus_cycles", [])
            report["passed"] &= report["focus_cycles"] == [1]
    finally:
        finish_run(protected, report, output)
    print(json.dumps({key: report[key] for key in ("passed", "restored")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
