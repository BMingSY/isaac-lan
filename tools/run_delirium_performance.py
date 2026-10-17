#!/usr/bin/env python3
"""Reproduce native Delirium with protected game processes and per-peer logs."""

import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command
from lab_profile import validate_labs as validate_owned_labs
from lab_profile import ProtectedLabs, idle
from game_logs import log_path

ROOT = Path(__file__).resolve().parents[1]


def reference(path):
    text = path.read_text(errors="replace").split("Room 5.3414(Delirium)", 1)[0]
    inventories = {0: Counter(), 1: Counter()}
    for action, item, slot in re.findall(
        r"(Adding|Removing) collectible (\d+) .*? (?:to|from) player (\d+)", text
    ):
        if int(slot) in inventories:
            inventories[int(slot)][int(item)] += 1 if action == "Adding" else -1
    loadouts = {
        slot: [item for item, count in sorted(values.items()) for _ in range(max(0, count))]
        for slot, values in inventories.items()
    }
    mods = sorted(
        set(re.findall(r"Running Lua Script: .*?[/\\]mods[/\\]([^/\\]+)[/\\]main.lua", text))
    )
    return loadouts, mods


def samples(output):
    """Align all peers with the shared Windows monotonic clock, not file order."""
    host_log = output / "engine/host/log.txt"
    if not host_log.exists():
        return {}
    host_text = host_log.read_text(errors="replace")
    phases = [
        (int(now), name)
        for name, now in re.findall(r"DELIRIUM_PERF PHASE name=(\S+) now_ms=(\d+)", host_text)
    ]
    result = {}
    for role in ("host", "client", "client2", "client3"):
        path = output / "engine" / role / "log.txt"
        if not path.exists():
            continue
        text = path.read_text(errors="replace")
        rows = [
            dict(re.findall(r"(\w+)=([^\s]+)", line))
            for line in text.splitlines()
            if "DELIRIUM_PERF SAMPLE" in line
        ]
        for row in rows:
            row["phase"] = next(
                (name for now, name in reversed(phases) if int(row["now_ms"]) >= now), "setup"
            )
        if not rows:
            continue
        with (output / f"{role}-samples.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)
        result[role] = {
            "native_form_changes": text.count("Changed Delirium form"),
            "phases": {},
        }
        for _, name in phases:
            values = [row for row in rows if row["phase"] == name]
            if not values:
                continue
            result[role]["phases"][name] = {
                "samples": len(values),
                "max_ping_ms": max(int(row["ping"]) for row in values),
                "max_ui_interval_ms": max(int(row["render_max_ms"]) for row in values),
                "max_projectiles": max(int(row["projectiles"]) for row in values),
                "max_raw_bytes": max(int(row["raw"]) for row in values),
                "min_boss_hp": min(float(row["boss_hp"]) for row in values),
                "max_boss_hp": max(float(row["boss_hp"]) for row in values),
                "max_boss_health_ratio": max(
                    (
                        float(row["boss_hp"]) / float(row["boss_max_hp"])
                        for row in values
                        if float(row["boss_max_hp"]) > 0
                    ),
                    default=0,
                ),
                "movement_range_pixels": max(
                    (
                        max(float(row[key]) for row in values)
                        - min(float(row[key]) for row in values)
                        for key in ("player_x", "player_y")
                        if key in values[0]
                    ),
                    default=0,
                ),
            }
    return result


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--extra-client", type=Path, action="append", default=[])
    parser.add_argument("--record-relay", action="store_true")
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--latency-ms", type=int, default=40)
    parser.add_argument("--port", type=int, default=31020)
    parser.add_argument(
        "--bandwidth-low-health",
        type=int,
        default=0,
        help="Extra low-health phase with this downstream bytes/sec limit",
    )
    parser.add_argument("--record-client", action="store_true")
    parser.add_argument("--reference-log", type=Path)
    parser.add_argument("--mods-directory", type=Path)
    parser.add_argument("--mod", type=Path, action="append", default=[])
    parser.add_argument("--installed-directory", type=Path)
    args = parser.parse_args()
    if not 10 <= args.seconds <= 300:
        parser.error("Combat seconds must be between 10 and 300")
    if args.bandwidth_low_health < 0 or args.bandwidth_low_health and not args.latency_ms:
        parser.error("A bandwidth phase requires the delayed relay and a nonnegative byte rate")
    labs = validate_owned_labs(
        [args.host.resolve(), args.client.resolve(), *(p.resolve() for p in args.extra_client)],
        args.output.resolve(),
        count=None,
    )
    roles = ("host", "client", "client2", "client3")[: len(labs)]
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    loadouts, mod_names = reference(args.reference_log) if args.reference_log else ({}, [])
    for slot in range(2, len(labs)):
        loadouts[slot] = list(loadouts.get(1, []))
    mods = list(args.mod)
    if args.mods_directory:
        mods.extend(args.mods_directory / name for name in mod_names)
    script = output / "fixture.lua"
    script.write_text(
        "_IsaacLanDeliriumFixture = { seconds = "
        + str(args.seconds)
        + ", bandwidth = "
        + str(args.bandwidth_low_health)
        + ", loadouts = {"
        + ",".join(f"[{slot}]={{{','.join(map(str, items))}}}" for slot, items in loadouts.items())
        + "} }\n"
        + (ROOT / "tests/state_delirium_performance.lua").read_text()
    )
    luac = shutil.which("luac5.3") or shutil.which("luac")
    if not luac:
        parser.error("Lua compiler is required")
    subprocess.run([luac, "-p", str(script)], check=True)
    build = args.build.resolve()
    if args.installed_directory:
        build = output / "installed-build"
        build.mkdir()
        for name in ("isaac_lan_probe.dll", "winmm.dll"):
            shutil.copy2(args.installed_directory / name, build / name)
        shutil.copy2(args.build / "isaac_lan_lab.exe", build)
    protected = ProtectedLabs(labs, output, roles=roles)
    command = engine_command(
        labs,
        build,
        output / "engine",
        script,
        "LAN_NETWORK DELIRIUM_PERF PASS Delirium performance reproduction",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--no-luadebug",
        "--automatic",
        "--performance",
        "--debug-logs",
        "--endings-fixture",
        "--hush-fixture",
        "--latency-ms",
        str(args.latency_ms),
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        str(240 + args.seconds * (3 if args.bandwidth_low_health else 2)),
    )
    for mod in dict.fromkeys(path.resolve() for path in mods):
        command.extend(("--mod", str(mod)))
    for lab in labs[2:]:
        command.extend(("--extra-client", str(lab)))
    if args.record_relay:
        command.append("--record-relay")
    control = output / "relay-control.json"

    def write_rate(rate):
        staged = control.with_suffix(".tmp")
        staged.write_text(json.dumps({"downstream_bytes_per_second": rate}))
        staged.replace(control)

    if args.bandwidth_low_health:
        write_rate(0)
        command.extend(("--relay-control", str(control)))
    if args.record_client:
        command.extend(("--native-record-view", "1", "--frame-ms", "250"))
    report = {
        "passed": False,
        "restored": False,
        "command": command,
        "dll_sha256": hashlib.sha256((build / "isaac_lan_probe.dll").read_bytes()).hexdigest(),
        "reference_loadouts": loadouts,
        "reference_mods": mod_names,
        "relay_bandwidth_events": [],
        "limitations": [
            "Loadouts inferred from native add/remove logs; trinkets, consumables and RNG state are not reconstructed.",
            "Preparation stages directly to the native Void and seeds an encounter history in an owned fixture.",
            "The local delay relay preserves throughput; it does not reproduce a specific frp server or its bandwidth.",
        ],
    }
    process = None
    try:
        for lab in labs:
            options = log_path(lab).parent / "options.ini"
            text = options.read_text()
            text = re.sub(r"(?m)^PopUps=.*$", "PopUps=0", text)
            options.write_text(text)
        with (output / "engine.log").open("w") as stream:
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
            last_rate = 0
            while process.poll() is None:
                if args.bandwidth_low_health:
                    path = log_path(labs[0])
                    text = path.read_text(errors="replace") if path.exists() else ""
                    phases = re.findall(r"DELIRIUM_PERF PHASE name=(\S+) now_ms=(\d+)", text)
                    phase, now = phases[-1] if phases else ("setup", "0")
                    rate = args.bandwidth_low_health if phase == "combat-bandwidth" else 0
                    if rate != last_rate:
                        write_rate(rate)
                        last_rate = rate
                        report["relay_bandwidth_events"].append(
                            {"phase": phase, "now_ms": int(now), "bytes_per_second": rate}
                        )
                time.sleep(0.2)
        report["passed"] = process.returncode == 0
        result_path = output / "engine/result.json"
        if result_path.exists():
            report["engine"] = json.loads(result_path.read_text())
        report["samples"] = samples(output)
        if report["passed"]:
            observed = report["samples"]
            checks = {
                "native_forms_observed": observed["host"]["native_form_changes"] > 0,
                "low_health_applied": observed["host"]["phases"]["combat-low-health"][
                    "max_boss_health_ratio"
                ]
                <= 0.25,
                "all_players_moved": all(
                    observed[role]["phases"]["combat"]["movement_range_pixels"] > 20
                    for role in roles
                ),
            }
            report["fixture_checks"] = checks
            report["passed"] = all(checks.values())
    finally:
        finish_run(protected, report, output, process=process)
    print(
        json.dumps(
            {
                "passed": report["passed"],
                "restored": report["restored"],
                "report": str(output / "report.json"),
            }
        )
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
