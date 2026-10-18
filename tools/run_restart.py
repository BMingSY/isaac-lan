#!/usr/bin/env python3
"""Check unanimous restarts and native keyboard/controller input with one owned pair."""

import argparse
import json
from pathlib import Path
import subprocess
import time

from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup, windows
from testing.engine import configure_interrupts, engine_command, engine_process
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]
COMPLETION = "LAN_NETWORK RESTART PASS six unanimous restarts"


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30792)
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.port < 65535:
        parser.error("Invalid port")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output)
    report = {"passed": False, "protected": protected.report(), "keyboard": []}
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        ROOT / "tests/state_restart.lua",
        COMPLETION,
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "240",
    )
    if args.record:
        command += ["--native-record-both", "--frame-ms", "250"]
    if args.heap_check:
        command.append("--heap-check")
    report["command"] = command
    handled = set()
    try:
        with (
            (output / "runner.log").open("w") as log,
            engine_process(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT) as process,
        ):
            while process.poll() is None:
                runner = (output / "runner.log").read_text(errors="replace")
                for lab, role in zip(labs, ("host", "client"), strict=True):
                    game_log = (
                        lab / "profile/Documents/My Games/Binding of Isaac Repentance+/log.txt"
                    )
                    text = game_log.read_text(errors="replace") if game_log.exists() else ""
                    for run in (2, 5):
                        key = (role, run)
                        marker = f"LAN_NETWORK RESTART KEYBOARD_READY run={run}"
                        if key in handled or marker not in text:
                            continue
                        prefix = f"Started isolated {role}: "
                        line = next(
                            value for value in runner.splitlines() if value.startswith(prefix)
                        )
                        pid = int(line[len(prefix) :])
                        # lab_window validates ownership and foreground before injection.
                        keypress = subprocess.run(
                            [
                                "powershell.exe",
                                "-NoProfile",
                                "-ExecutionPolicy",
                                "Bypass",
                                "-File",
                                windows(ROOT / "tools/lab_window.ps1"),
                                "-GameProcessId",
                                str(pid),
                                "-Action",
                                "Keys",
                                "-Value",
                                "R",
                                "-HoldMilliseconds",
                                "1000",
                            ],
                            check=True,
                            capture_output=True,
                            text=True,
                        )
                        handled.add(key)
                        report["keyboard"].append(
                            {
                                "role": role,
                                "run": run,
                                "pid": pid,
                                "stdout": keypress.stdout,
                                "stderr": keypress.stderr,
                            }
                        )
                time.sleep(0.1)
            report["returncode"] = process.returncode
        result = json.loads((output / "engine/result.json").read_text())
        report["engine"] = result
        report["passed"] = result["pass"] and len(handled) == 4
    finally:
        finish_run(protected, report, output)
    print(json.dumps({"passed": report["passed"], "restored": report["restored"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
