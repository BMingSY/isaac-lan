#!/usr/bin/env python3
"""Validate Lazarus, poop, knife chase and Hush with one protected native pair."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
from build_special_suite import CASES, DIAGNOSTICS, build
from run_endings import hashes, idle

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mod", type=Path, action="append", default=[])
    parser.add_argument("--case", choices=CASES + DIAGNOSTICS, action="append")
    parser.add_argument("--port", type=int, default=30220)
    args = parser.parse_args()
    cases = args.case or CASES
    if len(set(cases)) != len(cases):
        parser.error("Each case must appear once")
    if "home" in cases and cases[-1] != "home":
        parser.error("The native ending diagnostic must run last")
    labs = [args.host.resolve(), args.client.resolve()]
    if labs[0] == labs[1] or any(not (lab / ".isaac-lan-lab").is_file() for lab in labs):
        parser.error("Two distinct marked isolated labs are required")
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script = output / "suite.lua"
    build(script, cases)
    protected = []
    for role, lab in zip(("host", "client"), labs):
        for folder in ("profile", "game/data", "game/isaac-lan"):
            source = lab / folder
            backup = output / "before" / role / folder
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
        "LAN_NETWORK PASS all selected character and side routes",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--no-luadebug",
        "--automatic",
        "--progress-fixture",
        "--alt-path-fixture",
        "--hush-fixture",
        "--native-record-both",
        "--frame-ms",
        "250",
        "--latency-ms",
        "75",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "900",
    ]
    for mod in args.mod:
        command += ["--mod", str(mod.resolve())]
    report = {"passed": False, "restored": False, "cases": {}, "command": command}
    try:
        with (output / "engine.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        for index, name in enumerate(cases, 1):
            report["cases"][name] = {}
            for role in ("host", "client"):
                path = output / "engine" / role / "log.txt"
                text = path.read_text(errors="replace") if path.exists() else ""
                report["cases"][name][role] = {
                    "passed": "SPECIAL_CASE_PASS index=" + str(index) in text,
                    "checkpoints": [
                        line
                        for line in text.splitlines()
                        if (
                            "SIDE " + name + " " in line
                            or name == "home"
                            and "ENDINGS ascent " in line
                            or name == "audio"
                            and "LAN_NETWORK " in line
                            and "SIDE " not in line
                            or name == "lazarus"
                            and "LAN_NETWORK " in line
                            and "SIDE " not in line
                        )
                    ],
                }
        report["passed"] = result.returncode == 0 and all(
            peer["passed"] for case in report["cases"].values() for peer in case.values()
        )
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
