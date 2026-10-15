#!/usr/bin/env python3
"""Run an owned Boss shard, record both peers, and restore all isolated saves."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

from build_boss_suite import build
from run_endings import hashes, idle

ROOT = Path(__file__).resolve().parents[1]
COMPLETION = "LAN_NETWORK PASS all selected Boss encounters"


def evidence(text, cases):
    matches = re.findall(r"ALL_BOSSES PASS key=([\w-]+) live=(\d+) visible=(\d+) views=(\d+)", text)
    found = {
        key: {"live": int(live), "visible": int(visible), "views": int(views)}
        for key, live, visible, views in matches
    }
    expected = {case["key"] for case in cases}
    return {
        "passed": COMPLETION in text
        and set(found) == expected
        and len(matches) == len(expected)
        and all(value["live"] >= 30 and value["visible"] >= 10 for value in found.values())
        and "LAN_NETWORK FAILED" not in text,
        "missing": sorted(expected - found.keys()),
        "duplicates": sorted(
            key for key, count in Counter(match[0] for match in matches).items() if count > 1
        ),
        "cases": found,
        "forms": re.findall(r"ALL_BOSSES FORM key=([\w-]+) entity=([\d:]+)", text),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30600)
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shards", type=int, default=1)
    parser.add_argument("--case", action="append")
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    labs = [args.host.resolve(), args.client.resolve()]
    if len(set(labs)) != 2 or any(not (lab / ".isaac-lan-lab").is_file() for lab in labs):
        parser.error("Two distinct marked isolated labs are required")
    if any(lab.name.casefold() in {"host-001", "client-001"} for lab in labs):
        parser.error("host-001/client-001 are reserved for manual games")
    output = args.output.resolve()
    if any(output.is_relative_to(lab) or lab.is_relative_to(output) for lab in labs):
        parser.error("Evidence directory must be separate from the selected labs")
    idle(labs)
    output.mkdir(parents=True, exist_ok=False)
    script = output / "bosses.lua"
    cases = build(script, args.shard, args.shards, args.case)
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
        COMPLETION,
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--automatic",
        "--endings-fixture",
        "--native-record-both",
        "--frame-ms",
        "1000",
        "--latency-ms",
        "20",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "3600",
    ]
    if args.heap_check:
        command.append("--heap-check")
    report = {
        "passed": False,
        "restored": False,
        "shard": args.shard,
        "shards": args.shards,
        "cases": cases,
        "command": command,
    }
    try:
        with (output / "engine.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        report["peers"] = {}
        for role in ("host", "client"):
            path = output / "engine" / role / "log.txt"
            report["peers"][role] = evidence(
                path.read_text(errors="replace") if path.exists() else "", cases
            )
        report["passed"] = result.returncode == 0 and all(
            peer["passed"] for peer in report["peers"].values()
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
    print(json.dumps({key: report[key] for key in ("passed", "restored")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
