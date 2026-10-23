#!/usr/bin/env python3
"""Verify mouse capture/aiming and connection preferences in owned Windows labs."""

import argparse
import configparser
import json
from pathlib import Path
import re
import subprocess
import time
from game_logs import log_path
from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup, windows
from testing.engine import configure_interrupts, engine_command, engine_process
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]


def ready_peers(launch_log, labs):
    pids = dict(re.findall(r"Started isolated (host|client): (\d+)", launch_log.read_text()))
    # A new backend removes old game logs while starting each process. Do not
    # inspect last round's READY markers before both new PIDs are announced.
    if set(pids) != {"host", "client"}:
        return None
    for lab in labs:
        try:
            log = log_path(lab).read_text(errors="replace")
        except FileNotFoundError:
            return None
        if "LAN_NETWORK MOUSE READY" not in log:
            return None
    return pids


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=31640)
    args = parser.parse_args()
    configure_interrupts()
    labs = validate_labs([args.host, args.client], args.output)
    idle(labs)
    validate_startup(labs)
    args.output.mkdir(parents=True, exist_ok=False)
    markers = [
        lab / "game" / name
        for lab in labs
        for name in ("lan-test-mouse.done", "lan-test-connection-reload")
    ]
    if any(path.exists() for path in markers):
        raise RuntimeError("Remove stale mouse fixture markers before running")
    protected = ProtectedLabs(labs, args.output)
    report = {
        "passed": False,
        "restored": False,
        "protected": protected.report(),
        "rounds": [],
        "restart_reason": "Second process launch verifies connection preferences persisted to disk",
    }
    try:
        for lab in labs:
            path = lab / "profile/Documents/My Games/Binding of Isaac Repentance+/options.ini"
            options = configparser.ConfigParser()
            options.optionxform = str
            options.read(path)
            options["Options"]["MouseControl"] = "1"
            with path.open("w") as file:
                options.write(file)
        for round_index in range(2):
            output = args.output / f"round-{round_index + 1:02}"
            for lab in labs:
                (lab / "game/lan-test-mouse.done").unlink(missing_ok=True)
                if round_index:
                    (lab / "game/lan-test-connection-reload").touch()
            command = engine_command(
                labs,
                args.build,
                output,
                ROOT / "tests/state_mouse_input.lua",
                "LAN_NETWORK MOUSE PASS",
                "--frontend",
                "--menu-start",
                "--virtual-input",
                "--menu-port",
                str(args.port),
                "--heap-check",
                "--native-record-both",
                "--frame-ms",
                "100",
                "--scenario-timeout",
                "150",
            )
            record = {"command": command}
            report["rounds"].append(record)
            launch_log = args.output / f"round-{round_index + 1:02}.log"
            with (
                launch_log.open("w") as log,
                engine_process(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT) as process,
            ):
                deadline = time.monotonic() + 180
                while True:
                    if process.poll() is not None:
                        raise RuntimeError("Native runner exited before mouse interaction")
                    pids = ready_peers(launch_log, labs)
                    if pids:
                        break
                    if time.monotonic() > deadline:
                        raise RuntimeError("Mouse fixture never became ready")
                    time.sleep(0.2)
                for role, positions in (
                    ("client", ("720,220:720,220", "230,220:230,220")),
                    ("host", ("500,100:500,100", "500,420:500,420")),
                ):
                    for position in positions:
                        interaction = subprocess.run(
                            [
                                "powershell.exe",
                                "-NoProfile",
                                "-ExecutionPolicy",
                                "Bypass",
                                "-File",
                                windows(ROOT / "tools/lab_window.ps1"),
                                "-GameProcessId",
                                pids[role],
                                "-Action",
                                "Drag",
                                "-Value",
                                position,
                            ],
                            capture_output=True,
                            timeout=20,
                        )
                        transcript = interaction.stdout + interaction.stderr
                        with (args.output / "mouse-interaction.log").open("ab") as interaction_log:
                            interaction_log.write(transcript)
                        if interaction.returncode:
                            result_path = output / "result.json"
                            if result_path.is_file():
                                record["engine"] = json.loads(result_path.read_text())
                                if record["engine"].get("error"):
                                    raise RuntimeError(record["engine"]["error"])
                            raise RuntimeError(transcript.decode("utf-8", errors="replace"))
                        time.sleep(0.4)
                for lab in labs:
                    (lab / "game/lan-test-mouse.done").touch()
                record["returncode"] = process.wait(timeout=90)
            record["engine"] = json.loads((output / "result.json").read_text())
            assert record["returncode"] == 0 and record["engine"]["pass"], (
                "Native mouse fixture failed"
            )
            if round_index:
                for role in ("host", "client"):
                    assert "MOUSE PREFERENCES_RELOADED" in (output / role / "log.txt").read_text(
                        errors="replace"
                    )
        report["passed"] = True
    finally:
        for path in markers:
            path.unlink(missing_ok=True)
        finish_run(protected, report, args.output)
    print(
        json.dumps({name: report.get(name) for name in ("passed", "restored", "status", "error")})
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
