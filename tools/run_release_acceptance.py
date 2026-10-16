#!/usr/bin/env python3
"""Concentrated release checks using one installed, protected native pair."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys

from lab_profile import ProtectedLabs, idle
from game_logs import log_path
from lab_profile import windows
from run_pause_menu import magdalene_profile, peer_evidence as pause_evidence

ROOT = Path(__file__).resolve().parents[1]
HOURGLASS = (
    "cross-floor",
    "greed-start",
    "greed-neighbor",
    "greedier-start",
    "greedier-neighbor",
)
CASES = ("smoke", *HOURGLASS, "pause", "solo")
COMPLETION = "LAN_NETWORK PASS all selected character and side routes"


def build_suite(output, coordination, cases=CASES):
    """Keep each fixture's callbacks and frame/gate wrappers inside its factory."""
    factories = []
    for name in cases:
        prefix = ""
        filename = "state_release_" + name + ".lua"
        if name in HOURGLASS:
            filename = "state_release_hourglass.lua"
            prefix = "_IsaacLanTest.releaseHourglass = " + json.dumps(name) + "\n"
        elif name == "pause":
            filename = "state_pause_menu.lua"
            prefix = (
                "local pauseCoordination = "
                + json.dumps(windows(coordination / "pause").replace("\\", "/"))
                + "\nlocal pausePulses = 8\n"
            )
        elif name == "solo":
            prefix = (
                "_IsaacLanTest.releaseCoordination = "
                + json.dumps(windows(coordination).replace("\\", "/"))
                + "\n"
            )
        source = (ROOT / "tests" / filename).read_text()
        factories.append(
            "function()\nlocal registered, addCallback = {}, Isaac.AddCallback\n"
            "Isaac.AddCallback = function(owner, id, callback, parameter)\n"
            "registered[#registered + 1] = {owner, id, callback}\n"
            "return addCallback(owner, id, callback, parameter) end\n"
            + prefix
            + source
            + "\nIsaac.AddCallback = addCallback\nlocal cleaned = false\n"
            "return function()\nif finished and not cleaned then\ncleaned = true\n"
            "for _, callback in ipairs(registered) do\n"
            "Isaac.RemoveCallback(callback[1], callback[2], callback[3]) end\n"
            "native.test_gamepad(0) end\nreturn finished end end"
        )
    output.write_text(
        "local fixtures = {\n"
        + ",\n".join(factories)
        + "\n}\n"
        + (ROOT / "tests/special_suite_driver.lua").read_text()
    )


def evidence(text, host, cases=CASES):
    required = [COMPLETION]
    if "smoke" in cases:
        required.append("RELEASE_SMOKE PASS authority=" + str(host).lower())
    required += ["SPECIAL_CASE_PASS index=" + str(index) for index in range(1, len(cases) + 1)]
    for name in (name for name in cases if name in HOURGLASS):
        prefix = "RELEASE_HOURGLASS case=" + name + " "
        required += [prefix + "PASS authority=" + str(host).lower()]
        required += [prefix + "WALK_PASS slot=" + str(slot) for slot in range(2)]
        required.append(prefix + ("RESULT_PASS " if host else "REPLICA_RESULT_PASS "))
        if not host:
            required.append(prefix + "SELECTED_NATIVE ")
    if "solo" in cases:
        required += [
            "RELEASE_SOLO NEW_RUN_STARTED continued=false",
            "RELEASE_SOLO CONTINUE_PASS continued=true",
            "RELEASE_SOLO SAVE_EXIT_CALLBACK sequence=1 should_save=true",
            "RELEASE_SOLO SAVE_EXIT_CALLBACK sequence=2 should_save=true",
            "RELEASE_SOLO PASS native_new_run=true native_save_exit=true native_continue=true lan_between=true",
        ]
    pause = pause_evidence(text, host, 8) if "pause" in cases else {"passed": True, "skipped": True}
    missing = [marker for marker in required if marker not in text]
    return {
        "passed": not missing and pause["passed"] and "LAN_NETWORK FAILED" not in text,
        "missing": missing,
        "pause": pause,
        "evidence": [
            line
            for line in text.splitlines()
            if any(marker in line for marker in ("RELEASE_", "SOLO_", "SPECIAL_CASE_PASS"))
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30480)
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--heap-check", action="store_true")
    parser.add_argument("--cases", choices=CASES, nargs="+", default=CASES)
    args = parser.parse_args()
    if len(set(args.cases)) != len(args.cases):
        parser.error("Each case may only be selected once")
    labs = [args.host.resolve(), args.client.resolve()]
    if len(set(labs)) != 2 or any(not (lab / ".isaac-lan-lab").is_file() for lab in labs):
        parser.error("Two distinct owned labs are required")
    if any(lab.name.casefold() in {"host-001", "client-001"} for lab in labs):
        parser.error("Manual host-001/client-001 games must not be controlled")
    output = args.output.resolve()
    if any(output.is_relative_to(lab) or lab.is_relative_to(output) for lab in labs):
        parser.error("Evidence must be outside all selected labs")
    if not 1 <= args.port < 65535:
        parser.error("Invalid port")
    payload = json.loads((args.package / "payload.json").read_text())
    for name, digest in payload["files"].items():
        if hashlib.sha256((args.build / name).read_bytes()).hexdigest() != digest:
            parser.error("The built native files must match the frozen release package")
    idle(labs)
    progress = magdalene_profile(
        (log_path(labs[1]).parent / "persistentgamedata1.dat").read_bytes()
    )
    output.mkdir(parents=True, exist_ok=False)
    coordination = output / "coordination"
    (coordination / "pause").mkdir(parents=True)
    (coordination / "pause/step.txt").write_text("1")
    script = output / "suite.lua"
    build_suite(script, coordination, args.cases)
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
        COMPLETION,
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--installed",
        "--keyboard-pause",
        "--menu-port",
        str(args.port),
        "--release-solo-coordination",
        str(coordination),
        "--scenario-timeout",
        "1800",
    ]
    if args.record:
        command += ["--native-record-both", "--frame-ms", "250"]
    if args.heap_check:
        command.append("--heap-check")
    report = {
        "passed": False,
        "restored": False,
        "cases": args.cases,
        "payload": payload,
        "command": command,
    }
    process = None

    def interrupted(signum, _frame):
        raise RuntimeError("Release acceptance interrupted by signal " + str(signum))

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        (log_path(labs[1]).parent / "persistentgamedata1.dat").write_bytes(progress)
        for role, lab in zip(("host", "client"), labs):
            options = log_path(lab).parent / "options.ini"
            text = re.sub(r"(?m)^PopUps=.*$", "PopUps=0", options.read_text())
            text = re.sub(
                r"(?m)^MusicVolume=.*$", "MusicVolume=" + ("0.2" if role == "host" else "0"), text
            )
            options.write_text(text)
        with (output / "engine.log").open("w") as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            report["returncode"] = process.wait()
        engine = json.loads((output / "engine/result.json").read_text())
        report["peers"] = {
            role: evidence(
                (output / "engine" / role / "log.txt").read_text(errors="replace"),
                role == "host",
                args.cases,
            )
            for role in ("host", "client")
        }
        report["passed"] = report["returncode"] == 0 and all(
            peer["passed"] for peer in report["peers"].values()
        )
        if "solo" in args.cases:
            report["passed"] &= len(engine.get("preserved_solo_sha256", {})) == 2
    except Exception as error:
        report["error"] = str(error)
        if process and process.poll() is None:
            process.terminate()
            process.wait(timeout=180)
    finally:
        try:
            protected.restore()
            report["restored"] = True
        except Exception as error:
            report["restoration_error"], report["passed"] = str(error), False
        (output / "report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps({key: report[key] for key in ("passed", "restored")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
