#!/usr/bin/env python3
"""Check held-bag movement and current ambience in one protected LAN session."""

import argparse
import csv
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import sys

from run_endings import hashes, idle
from run_lan_challenges import profile_fixture

ROOT = Path(__file__).resolve().parents[1]


def build_scene_suite(output):
    """Reuse the EID-loaded pair for steady scenes and repeated bag transitions."""
    factories = []
    for name in ("state_scene_performance.lua", "state_bag_transitions.lua"):
        source = (ROOT / "tests" / name).read_text()
        source = source.replace(
            "eid = mod", "eid = mod; previousBagMode = eid.Config.DisplayBagOfCrafting"
        ).replace(
            "eid[name] = measure", "previousEidMethods[name] = eid[name]; eid[name] = measure"
        )
        if name == "state_bag_transitions.lua":
            source = source.replace(
                "lan-test-digest-scenes.csv", "lan-test-digest-bag-transitions.csv"
            )
        factories.append(
            "function()\n"
            "local previousSprite, previousPrediction = _IsaacLan.sprite_state, _IsaacLanPrediction.new\n"
            "local previousEidMethods, previousBagMode = {}, nil\n"
            + source
            + "\nlocal cleaned = false\nreturn function()\n"
            "if finished and not cleaned then\ncleaned = true\noutput:close()\n"
            "_IsaacLan.sprite_state, _IsaacLanPrediction.new = previousSprite, previousPrediction\n"
            "if eid then\nfor name, fn in pairs(previousEidMethods) do eid[name] = fn end\n"
            "eid.Config.DisplayBagOfCrafting = previousBagMode end\n"
            "native.test_gamepad(0) end\nreturn finished end end"
        )
    output.write_text(
        "local fixtures = {\n"
        + ",\n".join(factories)
        + "\n}\n"
        + (ROOT / "tests/special_suite_driver.lua").read_text()
    )


def measure_bag_transitions(path):
    rows = list(csv.DictReader(path.open()))
    report = []
    for cycle in range(8):
        for action, offset in (("raise", 6), ("lower", 42)):
            start = 216 + cycle * 72 + offset
            samples = [r for r in rows if start <= int(r["tick"]) < start + 12]
            assert len(samples) >= 15, f"Missing bag transition {cycle}: {action}"
            assert any((r["holding"] == "true") == (action == "raise") for r in samples)
            intervals = sorted(float(r["interval_ms"]) for r in samples)
            result = {
                "cycle": cycle,
                "action": action,
                "moving": cycle < 6,
                "eid": samples[-1]["phase"],
                "samples": len(samples),
                "prediction_resets": sum(int(r["prediction_resets"]) for r in samples),
                "max_interval_ms": max(intervals),
                "p95_interval_ms": intervals[int(len(intervals) * 0.95)],
            }
            assert result["prediction_resets"] == 0, result
            assert result["max_interval_ms"] < 50, result
            if cycle < 6:
                direction = 1 if action == "raise" else -1
                steps = [
                    direction * (float(b["x"]) - float(a["x"]))
                    for a, b in zip(samples, samples[1:])
                ]
                result["frozen_frames"] = sum(abs(step) < 0.001 for step in steps)
                result["min_forward_step"] = min(steps)
                assert min(steps) >= -0.01 and result["frozen_frames"] == 0, result
            report.append(result)
    return report


def measure(path, water_only=False):
    rows = list(csv.DictReader(path.open()))
    report = {}
    for phase, first, last in (
        ("bag_held", 420, 735),
        ("bag_no_eid_render", 780, 1035),
        ("water1", 1590, 2085),
        ("water2", 2460, 3045),
    ):
        if water_only and phase.startswith("bag"):
            continue
        samples = [r for r in rows if r["phase"] == phase and first <= int(r["tick"]) < last]
        assert len(samples) > 200, f"Missing scene: {phase}"
        intervals = sorted(float(r["interval_ms"]) for r in samples)
        result = {
            "samples": len(samples),
            "mean_interval_ms": statistics.mean(intervals),
            "p95_interval_ms": intervals[int(len(intervals) * 0.95)],
            "max_other_entities": max(int(r["other_entities"]) for r in samples),
            "max_local_spray": max(int(r["local_spray"]) for r in samples),
        }
        if phase.startswith("bag"):
            moving = [
                (a, b)
                for a, b in zip(samples, samples[1:])
                if 5 <= int(b["tick"]) % 72 < 17 or 41 <= int(b["tick"]) % 72 < 53
            ]
            assert moving and all(b["animation"].startswith("PickupWalk") for _, b in moving)
            result["frozen_moving_fraction"] = sum(
                abs(float(b["x"]) - float(a["x"])) < 0.001 for a, b in moving
            ) / len(moving)
            assert result["frozen_moving_fraction"] < 0.1, result
        else:
            assert all(float(r["current_y"]) != 0 for r in samples), "Missing native current"
            assert result["max_local_spray"] > 10, "Current spray disappeared"
            # Other entities include ordinary rain, ripples and room decoration.
            # Inspect the actual current spray's replica identity instead.
            result["max_replicated_spray"] = max(int(r["replicated_spray"]) for r in samples)
            assert result["max_replicated_spray"] == 0, "Current spray was replicated"
        report[phase] = result
    return report


def main():
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
    labs = [args.host.resolve(), args.client.resolve()]
    if len(set(labs)) != 2 or any(not (lab / ".isaac-lan-lab").is_file() for lab in labs):
        parser.error("Two distinct marked labs are required")
    if any(lab.name in {"host-001", "client-001"} for lab in labs):
        parser.error("Manual game labs must not be controlled")
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
    protected = []
    for role, lab in zip(("host", "client"), labs):
        for folder in ("profile", "game/data", "game/isaac-lan"):
            source, backup = lab / folder, output / "before" / role / folder
            protected.append((source, backup, hashes(source), source.exists()))
            if source.exists():
                shutil.copytree(source, backup)
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
        (
            "LAN_NETWORK PASS all selected character and side routes"
            if args.include_bag_transitions
            else "LAN_NETWORK SCENES PASS scene observation"
        ),
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
    ]
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
            report["returncode"] = subprocess.run(
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
    finally:
        try:
            idle(labs)
            for source, backup, baseline, existed in protected:
                if source.exists():
                    shutil.rmtree(source)
                if existed:
                    shutil.copytree(backup, source)
                assert hashes(source) == baseline, "Isolated save restoration differs"
            report["restored"] = True
        except Exception as error:
            report["restoration_error"], report["passed"] = str(error), False
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps({k: report.get(k) for k in ("passed", "restored", "error")}, ensure_ascii=False)
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
