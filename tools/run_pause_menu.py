#!/usr/bin/env python3
"""Exercise native pause submenus and lifecycle with one protected idle pair.

Only the selected owned labs may be launched. The user's host-001/client-001
manual games are always refused. All profile and LAN-save bytes are restored.
"""

import argparse
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile

from progress_fixture import MAGIC, checksum
from lab_profile import ProtectedLabs, idle
from game_logs import log_path
from lab_profile import windows

ROOT = Path(__file__).resolve().parents[1]
COMPLETION = "LAN_NETWORK PASS native pause menu"


def magdalene_profile(source):
    """Unlock only native Magdalene in a startup-only disposable profile."""
    if not 2800 <= len(source) <= 4 * 1024 * 1024 or source[:16] != MAGIC:
        raise ValueError("A native J460 progress baseline is required")
    if struct.unpack_from("<I", source, len(source) - 4)[0] != checksum(source[16:-4]):
        raise ValueError("Native progress checksum differs")
    if struct.unpack_from("<3I", source, 20) != (1, 642, 642):
        raise ValueError("Unsupported native achievement section")
    if any(flag > 1 for flag in source[32:674]):
        raise ValueError("Invalid native achievement flags")
    data = bytearray(source)
    data[32 + 1] = 1
    struct.pack_into("<I", data, len(data) - 4, checksum(data[16:-4]))
    return bytes(data)


def peer_evidence(text, host, pulses):
    required = [COMPLETION, "SHORT_PRESSES edges=" + str(pulses)]
    for name in (
        "guest-start",
        "guest-up-items",
        "guest-items",
        "guest-music-change",
        "guest-root-resume",
        "guest-root-exit",
        "host-resume-after-leave",
        "guest-rejoin",
        "host-root-exit",
        "ordinary-resume",
        "final-save-exit",
    ):
        required.append("PAUSE_MENU step=" + name + " CHECK ")
    required.append("ORDINARY_RESUME_PRESERVED" if host else "REJOIN_PRESERVED")
    return {
        "passed": all(marker in text for marker in required) and "LAN_NETWORK FAILED" not in text,
        "missing": [marker for marker in required if marker not in text],
        "evidence": [line for line in text.splitlines() if "PAUSE_MENU " in line],
    }


def main():
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
    labs = [args.host.resolve(), args.client.resolve()]
    if labs[0] == labs[1] or any(not (lab / ".isaac-lan-lab").is_file() for lab in labs):
        parser.error("Two distinct owned labs are required")
    if any(lab.name.casefold() in {"host-001", "client-001"} for lab in labs):
        parser.error("host-001/client-001 are reserved for the user's manual games")
    if not 2 <= args.pause_pulses <= 32 or args.pause_pulses % 2:
        parser.error("--pause-pulses must be an even integer from 2 to 32")
    if not 1 <= args.port < 65535 or not 16 <= args.frame_ms <= 1000:
        parser.error("Invalid port or frame interval")
    output = args.output.resolve()
    if any(output.is_relative_to(lab) or lab.is_relative_to(output) for lab in labs):
        parser.error("Evidence directory must be separate from the selected labs")
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
    ]
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
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
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
        try:
            protected.restore()
            report["restored"] = True
        except Exception as error:
            report["restoration_error"], report["passed"] = str(error), False
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ("passed", "restored")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
