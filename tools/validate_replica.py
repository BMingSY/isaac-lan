#!/usr/bin/env python3
"""Run the fixed two-client regressions; keep logs, input records and video.

Gameplay groups compatible fixtures into one native game. Lifecycle cases
remain isolated. Only normal uses ordinary menu/controller operations without
changing gameplay state.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from build_gameplay_suite import build as build_suite
from capture_suite_checkpoints import capture as capture_checkpoints
from archive_gameplay import archive

SOURCE = Path(__file__).resolve().parents[1]
LAB = Path("/mnt/d/isaac-lan-lab")
CASES = {
    "projection": ("state_projection.lua", "single-view special rooms and native floor transition"),
    "reconnect": ("state_reconnect.lua", "current-floor reconnect while host continues"),
    "reconnect-stage": (
        "state_reconnect_stage.lua",
        "reconnect follows floor changes during loading",
    ),
    "resume": ("state_resume.lua", "authoritative saved session"),
    "drop": ("state_drop_lobby.lua", "unexpected drop returns to LAN lobby then rejoins"),
    "arrival": ("state_arrival.lua", "door protection only when joining occupied combat"),
    "motion": ("state_motion.lua", "continuous local movement"),
    "input-response": ("state_input_response.lua", "immediate native input response"),
    "local-movement": ("state_local_movement.lua", "local movement and door arrival"),
    "visuals": ("state_guest_visuals.lua", "guest native revival visuals"),
    "mod-ui": ("state_mod_ui.lua", "local Mod map and room request"),
    "special-doors": ("state_special_doors.lua", "special door slots and raw-input Devil entry"),
    "white-fire": (
        "state_white_fire.lua",
        "native white-fire transformation and room-clear restoration",
    ),
    "peer-flash": ("state_peer_flash.lua", "peer native door viewport isolation"),
    "active-edges": ("state_active_edges.lua", "one physical active press"),
    "item-revive": ("state_item_revive.lua", "native Collar and Dead Cat resurrection"),
    "hourglass": ("state_hourglass.lua", "native full team hourglass"),
    "weapon-charge": ("state_weapon_charge.lua", "guest native charged weapon"),
    "peer-intro": ("state_peer_intro.lua", "peer native intro isolation"),
    "item-presentation": ("state_item_presentation.lua", "item presentation ownership"),
    "item-text": ("state_item_text.lua", "native guest pickup text"),
    "mirror-camera": ("state_mirror_camera.lua", "native mirror direction and large room camera"),
    "floor-items": ("state_floor_items.lua", "native Forget Me Now five-pip and R Key"),
}
DEFAULT_CASES = [
    "gameplay",
    "projection",
    "reconnect",
    "reconnect-stage",
    "resume",
    "drop",
    "visuals",
    "peer-flash",
    "normal",
]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument(
        "--cases", nargs="+", choices=[*CASES, "gameplay", "normal"], default=DEFAULT_CASES.copy()
    )
    p.add_argument("--latency-ms", type=int, default=75)
    p.add_argument("--ffmpeg", type=Path)
    p.add_argument(
        "--goodtrip",
        type=Path,
        help="Unmodified installed Good Trip directory; run simultaneous map/teleport regression on both peers",
    )
    a = p.parse_args()
    if not 0 <= a.latency_ms <= 1000:
        p.error("Latency must be 0..1000 ms")
    if len(set(a.cases)) != len(a.cases):
        p.error("Specify each case once")
    if a.goodtrip and "mod-ui" not in a.cases:
        a.cases.insert(a.cases.index("normal") if "normal" in a.cases else len(a.cases), "mod-ui")
    if "mod-ui" in a.cases and (not a.goodtrip or not (a.goodtrip / "main.lua").is_file()):
        p.error("mod-ui requires --goodtrip pointing to the installed Mod")
    a.output = a.output.resolve()
    a.output.mkdir(parents=True, exist_ok=False)
    build = SOURCE / "build-win32"
    dll = build / "isaac_lan_probe.dll"
    expected = hashlib.sha256(dll.read_bytes()).hexdigest()
    summary = {
        "pass": False,
        "dll_sha256": expected,
        "one_way_latency_ms": a.latency_ms,
        "cases": {},
        "visual_review_required": True,
    }
    try:
        for index, case in enumerate(a.cases):
            if hashlib.sha256(dll.read_bytes()).hexdigest() != expected:
                raise RuntimeError("Build changed during validation")
            output = a.output / case
            if case == "normal":
                cmd = [
                    sys.executable,
                    str(SOURCE / "tools/manual_gameplay.py"),
                    "run",
                    "--output",
                    str(output),
                    "--latency-ms",
                    str(a.latency_ms),
                ]
                if a.ffmpeg:
                    cmd += ["--ffmpeg", str(a.ffmpeg)]
                report = output / "report.json"
            else:
                if case == "gameplay":
                    script = a.output / "gameplay-suite.lua"
                    summary["gameplay_phases"] = build_suite(script)
                    completion = "continuous gameplay suite"
                else:
                    filename, completion = CASES[case]
                    script = SOURCE / "tests" / filename
                cmd = [
                    sys.executable,
                    str(SOURCE / "tools/run_network_engine.py"),
                    "--host",
                    str(LAB / "host-001"),
                    "--client",
                    str(LAB / "client-001"),
                    "--build",
                    str(build),
                    "--frontend",
                    "--menu-start",
                    "--script",
                    str(script),
                    "--completion",
                    "LAN_NETWORK PASS " + completion,
                    "--output",
                    str(output),
                    "--latency-ms",
                    str(a.latency_ms),
                    "--menu-port",
                    str(29536 + index * 10),
                ]
                if case == "projection":
                    cmd += ["--installed", "--check-local-stats", "--watch-floor-hud"]
                if case == "mod-ui":
                    cmd += ["--mod", str(a.goodtrip)]
                if case == "peer-flash":
                    cmd += ["--native-record-view", "0", "--frame-ms", "16"]
                if case in ("item-revive", "peer-intro"):
                    cmd += ["--native-record-view", "0", "--frame-ms", "50"]
                if case in ("item-presentation", "item-text"):
                    cmd += ["--native-record-both", "--frame-ms", "50"]
                if case in ("hourglass", "weapon-charge"):
                    cmd += ["--native-record-view", "1", "--frame-ms", "50"]
                if case == "mirror-camera":
                    cmd += ["--native-record-view", "1", "--frame-ms", "16"]
                if case == "gameplay":
                    cmd += ["--native-record-both", "--frame-ms", "50", "--scenario-timeout", "660"]
                if case == "floor-items":
                    cmd += [
                        "--native-record-view",
                        "1",
                        "--frame-ms",
                        "50",
                        "--scenario-timeout",
                        "150",
                    ]
                report = output / "result.json"
            print("Validating " + case, flush=True)
            result = subprocess.run(cmd)
            if report.exists():
                summary["cases"][case] = json.loads(report.read_text())
            if result.returncode:
                raise RuntimeError(case + " failed; inspect its frozen logs")
            value = summary["cases"][case]
            if value["dll_sha256"] != expected or not value.get(
                "pass", value.get("completed", False)
            ):
                raise RuntimeError(case + " did not verify the expected build")
            if case == "peer-flash" and a.ffmpeg:
                subprocess.run(
                    [
                        sys.executable,
                        str(SOURCE / "tools/check_peer_flash.py"),
                        str(output),
                        "--ffmpeg",
                        str(a.ffmpeg),
                    ],
                    check=True,
                )
                value["frame_review"] = json.loads((output / "flash-review.json").read_text())
            if case in ("motion", "gameplay"):
                subprocess.run(
                    [
                        sys.executable,
                        str(SOURCE / "tools/check_state_motion.py"),
                        str(output / "client/lan-test-digest-motion.csv"),
                        "--output",
                        str(output / "movement.json"),
                    ],
                    check=True,
                )
                value["movement"] = json.loads((output / "movement.json").read_text())
            if case == "input-response":
                subprocess.run(
                    [
                        sys.executable,
                        str(SOURCE / "tools/check_input_response.py"),
                        str(output / "client/lan-test-digest-response.csv"),
                        "--output",
                        str(output / "response.json"),
                    ],
                    check=True,
                )
                value["input_response"] = json.loads((output / "response.json").read_text())
            if case == "local-movement":
                subprocess.run(
                    [
                        sys.executable,
                        str(SOURCE / "tools/check_local_movement.py"),
                        str(output / "client/lan-test-digest-local-movement.csv"),
                        "--output",
                        str(output / "local-movement.json"),
                    ],
                    check=True,
                )
                value["local_movement"] = json.loads((output / "local-movement.json").read_text())
            if case in ("mirror-camera", "gameplay"):
                subprocess.run(
                    [
                        sys.executable,
                        str(SOURCE / "tools/check_mirror_camera.py"),
                        str(output / "client/lan-test-digest-camera.csv"),
                        "--output",
                        str(output / "camera-review.json"),
                    ],
                    check=True,
                )
                value["camera"] = json.loads((output / "camera-review.json").read_text())
            if case == "gameplay":
                value["native_game_starts"] = {}
                for role in ("host", "client"):
                    native = (
                        (output / role / "probe.log")
                        .read_text(errors="replace")
                        .rsplit("bootstrap=PASS", 1)[-1]
                    )
                    starts = native.count("network_engine_start=REQUESTED")
                    if starts != 1:
                        raise RuntimeError(f"{role}: suite started {starts} games instead of one")
                    value["native_game_starts"][role] = starts
                    log = (output / role / "log.txt").read_text(errors="replace")
                    for phase in summary["gameplay_phases"]:
                        if log.count("LAN_SUITE BEGIN " + phase["name"] + " tick=") != 1:
                            raise RuntimeError(
                                f"{role}: phase was not executed once: {phase['name']}"
                            )
                        if "LAN_SUITE " + phase["name"] + " LAN_NETWORK PASS " not in log:
                            raise RuntimeError(f"{role}: phase did not finish: {phase['name']}")
                value["rendered_checkpoints"] = capture_checkpoints(
                    output, script.with_suffix(".json")
                )
            if (
                case != "normal"
                and a.ffmpeg
                and any((output / role / "frames").exists() for role in ("host", "client"))
            ):
                value["recordings"] = archive(output, a.ffmpeg)
        summary["pass"] = True
    except Exception as error:
        summary["error"] = str(error)
        raise
    finally:
        (a.output / "validation.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
