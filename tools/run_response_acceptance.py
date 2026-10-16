#!/usr/bin/env python3
"""Validate response changes with one protected pair and one connection."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

from build_gameplay_suite import build
from check_input_response import measure as response_measure
from check_local_movement import measure as movement_measure
from check_state_motion import measure as motion_measure
from check_mirror_camera import check as camera_measure
from lab_profile import ProtectedLabs, idle
from game_logs import log_path

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    "input-response",
    "motion",
    "local-movement",
    "response-pause",
    "active-edges",
    "weapon-charge",
    "mirror-camera",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=31120)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--client-input-hz", type=int, choices=(30, 60), default=60)
    parser.add_argument("--record-view", action="store_true")
    args = parser.parse_args()
    labs = [args.host.resolve(), args.client.resolve()]
    if len(set(labs)) != 2 or any(not (lab / ".isaac-lan-lab").is_file() for lab in labs):
        parser.error("Two distinct marked labs are required")
    if any(lab.name in {"host-001", "client-001"} for lab in labs):
        parser.error("Manual game labs must not be controlled")
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script, relay = output / "suite.lua", output / "relay.json"
    phases = build(script, args.cases)
    switch_delay = "input-response" in args.cases
    relay.write_text(
        json.dumps({"downstream_bytes_per_second": 0, "delay_ms": 0 if switch_delay else 10})
    )
    # The fixture requests a delay change; the runner atomically replaces the
    # relay control file. No game writes or partially read JSON are involved.
    delay_tick = next(
        (phase["start"] + 300 for phase in phases if phase["name"] == "input-response"), 0
    )
    switch = f"""
local responseFrame, responseDelayChanged = _IsaacLanFrame, false
function _IsaacLanFrame()
    local status = responseFrame()
    if host and status.verified >= {delay_tick} and not responseDelayChanged then
        responseDelayChanged = true
        Isaac.DebugString("LAN_NETWORK RESPONSE_DELAY requested_one_way_ms=10")
    end
    return status
end
"""
    if switch_delay:
        script.write_text(script.read_text() + switch)
    subprocess.run([shutil.which("luac5.3") or "luac", "-p", str(script)], check=True)
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
        "LAN_NETWORK PASS continuous gameplay suite",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--performance",
        "--client-input-hz",
        str(args.client_input_hz),
        "--latency-ms",
        "10",
        "--relay-control",
        str(relay),
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "420",
    ]
    if args.record_view:
        command += ["--native-record-view", "1", "--frame-ms", "500"]
    report = {
        "passed": False,
        "restored": False,
        "phases": phases,
        "command": command,
        "client_input_hz": args.client_input_hz,
    }
    try:
        with (output / "engine.log").open("w") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            changed = False
            while process.poll() is None:
                path = log_path(labs[0])
                if (
                    switch_delay
                    and not changed
                    and path.exists()
                    and "RESPONSE_DELAY requested_one_way_ms=10" in path.read_text(errors="replace")
                ):
                    temporary = relay.with_suffix(".tmp")
                    temporary.write_text(
                        json.dumps({"downstream_bytes_per_second": 0, "delay_ms": 10})
                    )
                    temporary.replace(relay)
                    changed = True
                time.sleep(0.2)
            report["returncode"] = process.returncode
            report["delay_changed"] = changed
        engine = json.loads((output / "engine/result.json").read_text())
        assert not switch_delay or changed, "Low-latency phase was not reached"
        assert engine["pass"], engine.get("error", "Native response suite failed")
        client = output / "engine/client"
        if "input-response" in args.cases:
            response = response_measure(client / "lan-test-digest-response.csv")
            report["response"] = response
            assert (
                response["max_input_to_send_ms"] <= (34 if args.client_input_hz == 30 else 0)
                and response["max_input_to_preview_ms"] == 0
            ), response
            assert abs(response["input_samples_per_render"] - args.client_input_hz / 60) <= 0.05, (
                response
            )
            assert (
                response["acceleration_transitions_responding_same_frame"]
                >= 0.9 * response["acceleration_transitions"]
            ), response
        if "local-movement" in args.cases:
            movement = movement_measure(client / "lan-test-digest-local-movement.csv")
            report["movement"] = movement
            assert movement["max_speed_resurgence_after_release"] < 35, movement
            assert (
                movement["max_arrival_displacement"] < 25 and movement["rooms_after_arrival"] == 1
            ), movement
        if "motion" in args.cases:
            motion = motion_measure(client / "lan-test-digest-motion.csv")
            report["motion"] = motion
            assert motion["max_reverse_step"] < 2, motion
        if "mirror-camera" in args.cases:
            camera = camera_measure(client / "lan-test-digest-camera.csv")
            report["camera"] = camera
            assert camera["pass"], camera
        report["passed"] = True
    except Exception as error:
        report["error"] = str(error)
    finally:
        try:
            protected.restore()
            report["restored"] = True
        except Exception as error:
            report["restoration_error"], report["passed"] = str(error), False
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {key: report.get(key) for key in ("passed", "restored", "error")}, ensure_ascii=False
        )
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
