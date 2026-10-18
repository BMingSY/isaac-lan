#!/usr/bin/env python3
"""Run offline regressions only. Engine scenarios can be listed, never launched."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from testing.discovery import inventory

ROOT = Path(__file__).resolve().parents[1]


def engine_catalog():
    """Discover suites and fixtures without importing an executor."""
    return inventory()


def plan(build, report, profile, lua, *, sanitizers=False):
    python = sys.executable
    return [
        ("format", [python, "tools/format.py", "--check"]),
        ("syntax", [python, "tools/check_scripts.py"]),
        (
            "configure",
            [
                "cmake",
                "-S",
                str(ROOT),
                "-B",
                str(build),
                "-DISAAC_LAN_BUILD_ENGINE=OFF",
                "-DCMAKE_BUILD_TYPE=Debug",
                "-DISAAC_LAN_LUA=" + lua,
                *(
                    [
                        "-DCMAKE_CXX_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer",
                        "-DCMAKE_C_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer",
                    ]
                    if sanitizers
                    else []
                ),
            ],
        ),
        ("build", ["cmake", "--build", str(build), "--parallel", "2"]),
        (
            "core",
            [
                "ctest",
                "--test-dir",
                str(build),
                "--output-on-failure",
                "--output-junit",
                str(report / "ctest.xml"),
                "-L",
                "offline",
            ],
        ),
        (
            "scenarios",
            [
                python,
                "-m",
                "pytest",
                "--offline-profile",
                profile,
                "--offline-report-dir",
                str(report / "traces"),
                "--junitxml",
                str(report / "pytest.xml"),
                "--durations=10",
                "-q",
            ],
        ),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("fast", "full"), default="fast")
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build-offline")
    parser.add_argument("--report-dir", type=Path)
    parser.add_argument(
        "--sanitizers",
        action="store_true",
        help="Enable ASan/LSan/UBSan for the portable C++ build",
    )
    parser.add_argument(
        "--list", action="store_true", help="Collect Python cases without execution"
    )
    parser.add_argument("--list-engine", action="store_true", help="Read engine inventory only")
    args = parser.parse_args()
    if args.list_engine:
        print(json.dumps(engine_catalog(), ensure_ascii=False, indent=2))
        return 0
    environment = os.environ.copy()
    environment["PATH"] = (
        str(Path(sys.executable).parent) + os.pathsep + environment.get("PATH", "")
    )
    if args.sanitizers:
        environment.setdefault("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1")
        environment.setdefault("UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1")
    if args.list:
        return subprocess.run(
            [sys.executable, "-m", "pytest", "--collect-only", "-q"],
            cwd=ROOT,
            env=environment,
            check=False,
        ).returncode
    lua = shutil.which("lua5.3", path=environment["PATH"]) or shutil.which(
        "lua", path=environment["PATH"]
    )
    if not lua:
        parser.error("Lua 5.3 is required; no engine test will be used as a fallback")
    subprocess.run(
        [lua, "-e", 'assert(_VERSION == "Lua 5.3", "Lua 5.3 is required")'],
        env=environment,
        check=True,
    )
    report = args.report_dir or ROOT / "test-runs" / (
        datetime.now(timezone.utc).strftime("offline-%Y%m%d-%H%M%S-") + str(os.getpid())
    )
    report = report.resolve()
    report.mkdir(parents=True, exist_ok=False)
    summary = {
        "profile": args.profile,
        "sanitizers": args.sanitizers,
        "game_started": False,
        "passed": False,
        "stages": [],
    }
    try:
        for name, command in plan(
            args.build_dir.resolve(), report, args.profile, lua, sanitizers=args.sanitizers
        ):
            print(f"Running offline stage: {name}", flush=True)
            start = time.monotonic()
            stage = {"name": name, "command": command, "log": name + ".log"}
            summary["stages"].append(stage)
            with (report / stage["log"]).open("w") as log:
                with subprocess.Popen(
                    command,
                    cwd=ROOT,
                    env=environment,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                ) as process:
                    for line in process.stdout:
                        print(line, end="", flush=True)
                        log.write(line)
                    stage["returncode"] = process.wait()
            stage["seconds"] = round(time.monotonic() - start, 3)
            if stage["returncode"]:
                return stage["returncode"]
        summary["passed"] = True
        return 0
    finally:
        (report / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"Offline report: {report}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
