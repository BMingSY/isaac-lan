#!/usr/bin/env python3
"""Run six ending routes with one isolated pair and restore its test saves."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from build_ending_suite import build
from run_network_engine import windows

ROOT = Path(__file__).resolve().parents[1]
CASES = ("lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent")


def idle(labs):
    command = (
        "@(Get-Process -Name isaac-ng -ErrorAction SilentlyContinue | "
        "ForEach-Object { $_.Path }) | ConvertTo-Json -Compress"
    )
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    )
    paths = json.loads(result.stdout or "[]") or []
    if isinstance(paths, str):
        paths = [paths]
    if {windows(lab / "game/isaac-ng.exe").casefold() for lab in labs} & {
        path.casefold() for path in paths
    }:
        raise RuntimeError("The selected isolated lab already has a running game")


def hashes(directory):
    return {
        str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in directory.rglob("*")
        if p.is_file()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mod", type=Path, action="append", default=[])
    parser.add_argument("--port", type=int, default=30120)
    parser.add_argument(
        "--route",
        choices=CASES,
        action="append",
        help="Run selected routes when diagnosing a failure; default: all six",
    )
    args = parser.parse_args()
    cases = args.route or CASES
    if len(set(cases)) != len(cases):
        parser.error("Each selected route must appear once")
    labs = [args.host.resolve(), args.client.resolve()]
    if labs[0] == labs[1] or any(not (lab / ".isaac-lan-lab").is_file() for lab in labs):
        parser.error("Two distinct marked isolated labs are required")
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script = output / "suite.lua"
    build(script, args.route)
    protected = []
    for role, lab in zip(("host", "client"), labs):
        for folder in ("profile", "game/data", "game/isaac-lan"):
            source = lab / folder
            backup = output / "before" / role / folder
            baseline = hashes(source)
            protected.append((source, backup, baseline, source.exists()))
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
        "LAN_NETWORK PASS all selected native ending routes",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--no-luadebug",
        "--automatic",
        "--endings-fixture",
        "--native-record-both",
        "--frame-ms",
        "500",
        "--latency-ms",
        "75",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "1800",
    ]
    for mod in args.mod:
        command += ["--mod", str(mod.resolve())]
    report = {"passed": False, "restored": False, "routes": {}, "command": command}
    try:
        with (output / "engine.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        for name in cases:
            peers = {}
            for role in ("host", "client"):
                path = output / "engine" / role / "log.txt"
                text = path.read_text(errors="replace") if path.exists() else ""
                lines = [line for line in text.splitlines() if "ENDINGS " + name + " " in line]
                peers[role] = {
                    "win": any(
                        "NATIVE_WIN callback=MC_POST_GAME_END game_over=false" in line
                        for line in lines
                    ),
                    "cleanup": any(
                        "PASS native ending and session cleanup" in line for line in lines
                    ),
                    "progress": any("LOCAL_PROGRESS_RESTORED" in line for line in lines),
                    "checkpoints": lines,
                }
            report["routes"][name] = peers
        report["passed"] = result.returncode == 0 and all(
            peer["win"] and peer["cleanup"] and peer["progress"]
            for peers in report["routes"].values()
            for peer in peers.values()
        )
    finally:
        # Do not restore files beneath a surviving process, including if a
        # native crash prevented the runner from completing owned cleanup.
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
            report["restoration_error"] = str(error)
            report["passed"] = False
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                "passed": report["passed"],
                "restored": report["restored"],
                "report": str(output / "report.json"),
            },
            indent=2,
        )
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
