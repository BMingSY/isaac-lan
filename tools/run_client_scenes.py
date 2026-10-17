#!/usr/bin/env python3
"""Check held-bag movement and current ambience in one protected LAN session."""

import argparse
from testing.scenes import measure, measure_bag_transitions
from testing.scenes import build_scene_suite
import json
from pathlib import Path
import shutil
import subprocess

from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command, run_engine
from lab_profile import validate_labs as validate_owned_labs
from lab_profile import ProtectedLabs, idle
from testing.profiles import profile_fixture

ROOT = Path(__file__).resolve().parents[1]


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--eid", type=Path, required=True)
    parser.add_argument("--port", type=int, default=31220)
    parser.add_argument("--record-view", action="store_true")
    scenes = parser.add_mutually_exclusive_group()
    scenes.add_argument("--water-only", action="store_true", help="Only recheck current rooms")
    scenes.add_argument("--bag-transitions", action="store_true", help="Only check repeated raises")
    scenes.add_argument(
        "--include-bag-transitions", action="store_true", help="Check all scenes in one game pair"
    )
    args = parser.parse_args()
    labs = validate_owned_labs(
        [args.host.resolve(), args.client.resolve()], args.output.resolve(), count=None
    )
    if not (args.eid / "main.lua").is_file():
        parser.error("An existing EID installation is required")
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script = output / "scenario.lua"
    script.write_text(
        ("_IsaacLanTest.waterOnly = true\n" if args.water_only else "")
        + (
            ROOT
            / "tests"
            / (
                "state_bag_transitions.lua"
                if args.bag_transitions
                else "state_scene_performance.lua"
            )
        ).read_text()
    )
    if args.include_bag_transitions:
        build_scene_suite(script)
    subprocess.run([shutil.which("luac5.3") or "luac", "-p", str(script)], check=True)
    protected = ProtectedLabs(labs, output, roles=("host", "client"))
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        "LAN_NETWORK PASS all selected character and side routes"
        if args.include_bag_transitions
        else "LAN_NETWORK SCENES PASS scene observation",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--performance",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "420",
        "--mod",
        str(args.eid.resolve()),
    )
    if args.record_view:
        command += ["--native-record-view", "1", "--frame-ms", "500"]
    report = {"passed": False, "restored": False, "command": command}
    try:
        for lab in labs:
            path = (
                lab
                / "profile/Documents/My Games/Binding of Isaac Repentance+/persistentgamedata1.dat"
            )
            path.write_bytes(profile_fixture(path.read_bytes(), tainted_cain=True))
        with (output / "engine.log").open("w") as log:
            report["returncode"] = run_engine(
                command, stdout=log, stderr=subprocess.STDOUT
            ).returncode
        engine = json.loads((output / "engine/result.json").read_text())
        assert engine["pass"], engine.get("error", "Native scene observation failed")
        samples = output / "engine/client/lan-test-digest-scenes.csv"
        report["scenes"] = (
            measure_bag_transitions(samples)
            if args.bag_transitions
            else measure(samples, args.water_only)
        )
        if args.include_bag_transitions:
            report["bag_transitions"] = measure_bag_transitions(
                output / "engine/client/lan-test-digest-bag-transitions.csv"
            )
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
        report["error_type"] = type(error).__name__
    finally:
        finish_run(protected, report, output)
    print(
        json.dumps({k: report.get(k) for k in ("passed", "restored", "error")}, ensure_ascii=False)
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
