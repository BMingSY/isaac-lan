#!/usr/bin/env python3
"""Exercise shared item rewards and generated definitions in one protected pair."""

import argparse
import json
from pathlib import Path
import subprocess
import time

from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command
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
    parser.add_argument("--port", type=int, default=51840)
    parser.add_argument("--tm-passives-only", action="store_true")
    args = parser.parse_args()
    labs = validate_owned_labs(
        [args.host.resolve(), args.client.resolve()], args.output.resolve(), count=None
    )
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script = output / "scenario.lua"
    script.write_text(
        ("_IsaacLanTest.passivesOnly = true\n" if args.tm_passives_only else "")
        + (ROOT / "tests/state_issue_items.lua").read_text()
    )
    protected = ProtectedLabs(labs, output)
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        "PASS generated passive effects and native continuation"
        if args.tm_passives_only
        else "PASS shared rewards, Genesis, generated effects and native continuation",
        "--frontend",
        "--automatic",
        "--menu-start",
        "--virtual-input",
        "--menu-port",
        str(args.port),
        "--heap-check",
        "--native-record-both",
        "--frame-ms",
        "250",
        "--scenario-timeout",
        "300",
    )
    report = {"passed": False, "restored": False, "command": command}
    process = None
    try:
        # A directory at the temporary-file path forces a real open failure.
        # Remove it only after the fixture observes the retained pending save.
        blocked = [labs[0] / f"game/isaac-lan/session-{slot}.bin.tmp" for slot in range(4)]
        for path in blocked:
            path.mkdir(parents=True, exist_ok=False)
        with (output / "engine.log").open("w") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            while process.poll() is None:
                game_log = (
                    labs[0] / "profile/Documents/My Games/Binding of Isaac Repentance+/log.txt"
                )
                text = game_log.read_text(errors="replace") if game_log.exists() else ""
                if blocked and "LAN_NETWORK ISSUE_ITEMS SAVE_RETRY_READY" in text:
                    for path in blocked:
                        path.rmdir()
                    blocked.clear()
                    report["save_failure_observed"] = True
                time.sleep(0.2)
            report["returncode"] = process.returncode
        engine = json.loads((output / "engine/result.json").read_text())
        assert engine["pass"], engine.get("error", "Item acceptance failed")
        log = (output / "engine/host/log.txt").read_text(errors="replace")
        assert report.get("save_failure_observed") and "SAVE_RETRY_OK" in log, (
            "Save retry was not exercised"
        )
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
        report["error_type"] = type(error).__name__
    finally:
        finish_run(protected, report, output, process=process)
    print(
        json.dumps({k: report.get(k) for k in ("passed", "restored", "error")}, ensure_ascii=False)
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
