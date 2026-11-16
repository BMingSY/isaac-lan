#!/usr/bin/env python3
"""Validate animation consent with one owned pair and physical confirmation inputs."""

import argparse
import json
from pathlib import Path
import subprocess
import time

from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup, windows
from testing.engine import configure_interrupts, engine_command, engine_process
from testing.lua import literal
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=31970)
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--record", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("Invalid port")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    shared = output / "coordination"
    shared.mkdir()
    script = output / "suite.lua"
    script.write_text(
        "local skipCoordination = "
        + literal(windows(shared).replace("\\", "/"))
        + "\n"
        + (ROOT / "tests/state_animation_skip.lua").read_text()
    )
    protected = ProtectedLabs(labs, output)
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        "LAN_NETWORK SKIP PASS native keyboard, controller, solo, shared and floor skips",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "240",
    )
    if args.record:
        command += ["--native-record-both", "--frame-ms", "200"]
    if args.heap_check:
        command.append("--heap-check")
    report = {"passed": False, "protected": protected.report(), "command": command, "keyboard": []}
    handled = set()
    try:
        with (
            (output / "runner.log").open("w") as log,
            engine_process(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT) as process,
        ):
            while process.poll() is None:
                for marker in shared.glob("keyboard-*.txt"):
                    if marker.name in handled:
                        continue
                    text = (output / "runner.log").read_text(errors="replace")
                    line = next(
                        (
                            line
                            for line in text.splitlines()
                            if line.startswith("Started isolated host: ")
                        ),
                        None,
                    )
                    if line is None:
                        continue
                    pid = int(line.rsplit(" ", 1)[1])
                    value = {"SPACE": "{SPACE}", "ENTER": "{ENTER}"}[marker.read_text()]
                    result = subprocess.run(
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
                            value,
                            "-HoldMilliseconds",
                            "150",
                        ],
                        capture_output=True,
                        text=True,
                        check=True,
                        timeout=20,
                    )
                    handled.add(marker.name)
                    report["keyboard"].append(
                        {"marker": marker.name, "pid": pid, "stdout": result.stdout}
                    )
                time.sleep(0.1)
            report["returncode"] = process.returncode
        result = json.loads((output / "engine/result.json").read_text())
        report["engine"] = result
        report["passed"] = result["pass"] and len(handled) == 2
    finally:
        finish_run(protected, report, output)
    print(json.dumps({"passed": report["passed"], "restored": report["restored"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
