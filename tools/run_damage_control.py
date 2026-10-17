#!/usr/bin/env python3
"""Compare shield behavior in owned native solo runs; requires exclusive menu input."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from item_audit import ROOT, lua, select_cases
from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command
from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup


def main():
    configure_interrupts()
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
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
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
    )
    process = None
    try:
        with (output / "engine.log").open("w") as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
            report["returncode"] = process.wait()
        report["engine"] = json.loads((output / "engine/result.json").read_text())
        report["passed"] = report["returncode"] == 0 and report["engine"]["pass"]
    finally:
        finish_run(protected, report, output, process=process)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
