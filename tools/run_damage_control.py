#!/usr/bin/env python3
"""Compare shield behavior in owned native solo runs; requires exclusive menu input."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import signal
import subprocess
import sys

from item_audit import ROOT, lua, select_cases
from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup


def main():
    signal.signal(signal.SIGINT, signal.default_int_handler)
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("host", "client", "build", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--players", type=int, choices=(1, 2), default=1)
    parser.add_argument(
        "--floor-request-phase", choices=("post-update", "frame"), default="post-update"
    )
    args = parser.parse_args()
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    validate_startup(labs)
    idle(labs)
    output.mkdir(parents=True, exist_ok=False)
    coordination = output / "coordination"
    coordination.mkdir()
    catalog = json.loads((ROOT / "tests/fixtures/item_catalog.json").read_text())
    cases = select_cases(catalog, ["trinket:121", "collectible:313"], contexts=["host-same"])
    cases.sort(key=lambda case: case["kind"] != "trinket")
    script = output / "fixture.lua"
    script.write_text(
        "local controlPlayers = "
        + str(args.players)
        + "\nlocal controlFloorInFrame = "
        + lua(args.floor_request_phase == "frame")
        + "\nlocal controlCases = "
        + lua(cases)
        + "\n"
        + "local createDamageTrace = (function()\n"
        + (ROOT / "tests/fixtures/item_damage_trace.lua").read_text()
        + "\nend)()\n"
        + (ROOT / "tests/state_item_native_damage.lua").read_text()
    )
    subprocess.run([shutil.which("luac5.3") or "luac", "-p", str(script)], check=True)
    report = {
        "restored": False,
        "cases": cases,
        "players": args.players,
        "floor_request_phase": args.floor_request_phase,
        "dll_sha256": hashlib.sha256((args.build / "isaac_lan_probe.dll").read_bytes()).hexdigest(),
        "fixture_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
    }
    protected = ProtectedLabs(labs, output)
    (output / "backup.json").write_text(json.dumps(protected.report(), indent=2) + "\n")
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
        "LAN_NETWORK NATIVE_DAMAGE_CONTROL_COMPLETE",
        "--frontend",
        "--menu-start",
        "--automatic",
        "--virtual-input",
        "--release-solo-coordination",
        str(coordination),
        "--heap-check",
        "--native-record-both",
        "--frame-ms",
        "1000",
        "--scenario-timeout",
        "600",
    ]
    process = None
    try:
        with (output / "engine.log").open("w") as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
            report["returncode"] = process.wait()
        report["engine"] = json.loads((output / "engine/result.json").read_text())
    finally:
        try:
            if process is not None and process.poll() is None:
                # The child owns both game PIDs and handles SIGTERM by closing
                # them. Never kill that cleanup or restore beneath a live game.
                process.terminate()
                process.wait(timeout=60)
            restoration = protected.restore()
            (output / "restored.json").write_text(json.dumps(restoration, indent=2) + "\n")
            report["restored"] = True
        except Exception as error:
            report["restoration_error"] = str(error)
        finally:
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["engine"]["pass"] and report["restored"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
