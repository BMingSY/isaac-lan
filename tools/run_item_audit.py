#!/usr/bin/env python3
"""Audit collectibles, trinkets, cards and pills in two protected native processes."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

from item_audit import (
    COMPLETION,
    ROOT,
    build_fixture,
    catalog_from_log,
    events,
    select_cases,
    summarize_case,
    stress_cases,
    unexpected_peer_failure,
)
from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command
from lab_profile import ProtectedLabs, idle, windows, validate_labs, validate_startup
from item_effect_checks import SUPPORTED_EFFECTS


def run_batch(args, cases, output, labs):
    output.mkdir(parents=True, exist_ok=False)
    script = output / "fixture.lua"
    journals = {role: output / (role + "-events.log") for role in ("host", "client")}
    build_fixture(
        script,
        {
            "cases": cases,
            "journal": {role: windows(path) for role, path in journals.items()},
            "verifyCodec": args.verify_codec,
            "snapshotPrefix": windows(output / "codec-"),
        },
    )
    subprocess.run([shutil.which("luac5.3") or "luac", "-p", str(script)], check=True)
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        COMPLETION,
        "--frontend",
        "--automatic",
        "--menu-start",
        "--virtual-input",
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        str(args.timeout),
    )
    if args.record:
        command.extend(("--native-record-both", "--frame-ms", "1000"))
    if args.mode == "stress":
        command.append("--performance")
    if args.mode != "stress" or args.heap_check:
        command.append("--heap-check")
    protected = ProtectedLabs(labs, output)
    report = {
        "cases": cases,
        "command": command,
        "fixture_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
        "restored": False,
    }
    (output / "backup.json").write_text(json.dumps(protected.report(), indent=2) + "\n")
    process = None
    try:
        with (output / "engine.log").open("w") as stream:
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
            last_progress, last_event = time.monotonic(), None
            offsets, host_markers = {"host": 0, "client": 0}, []
            while process.poll() is None:
                recent = {}
                for role, path in journals.items():
                    text = ""
                    if path.exists():
                        with path.open("rb") as journal:
                            journal.seek(offsets[role])
                            chunk = journal.read()
                        complete = chunk.rfind(b"\n") + 1
                        offsets[role] += complete
                        text = chunk[:complete].decode(errors="replace")
                    recent[role] = events(text)
                records = recent["host"]
                host_markers.extend(
                    e for e in records if e["event"] in {"case_begin", "exit_requested"}
                )
                if records:
                    last_event, last_progress = records[-1], time.monotonic()
                    for marker in records:
                        if marker["event"] in {"case_begin", "problem", "case_end"}:
                            print(json.dumps(marker, ensure_ascii=False), flush=True)
                failure = unexpected_peer_failure(host_markers, recent["client"])
                if failure:
                    report["watchdog"] = (
                        "Peer failed during " + failure["key"] + "; stop to preserve case alignment"
                    )
                    process.terminate()
                    break
                if last_event and time.monotonic() - last_progress > 90:
                    report["watchdog"] = (
                        "No audit progress for 90 seconds; preserve the interrupted case"
                    )
                    process.terminate()
                    break
                time.sleep(0.5)
            process.wait(timeout=120)
        result = output / "engine/result.json"
        report["engine"] = (
            json.loads(result.read_text())
            if result.exists()
            else {"error": "Engine report missing"}
        )
        peers = {}
        for role in ("host", "client"):
            path = journals[role]
            text = path.read_text(errors="replace") if path.exists() else ""
            peers[role] = events(text)
            if role == "host":
                try:
                    catalog = catalog_from_log(text)
                    (output / "catalog.json").write_text(
                        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
                    )
                except ValueError as error:
                    report["catalog_error"] = str(error)
        report["results"] = [summarize_case(case, peers, report["engine"]) for case in cases]
        report["passed"] = (
            bool(report["engine"].get("pass"))
            and bool(report["results"])
            and all(result["status"] in {"verified", "basic_pass"} for result in report["results"])
        )
    finally:
        finish_run(protected, report, output, process=process)
    return report


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--mode", choices=("catalog", "mega", "sweep", "effects", "stress"), default="mega"
    )
    parser.add_argument("--catalog", type=Path, default=ROOT / "tests/fixtures/item_catalog.json")
    parser.add_argument("--case", action="append")
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shards", type=int, default=1)
    parser.add_argument(
        "--context",
        action="append",
        choices=("host-same", "host-split", "client-same", "client-split"),
    )
    parser.add_argument("--port", type=int, default=51900)
    parser.add_argument("--timeout", type=int, default=86400)
    parser.add_argument("--record", action="store_true")
    parser.add_argument(
        "--verify-codec",
        action="store_true",
        help="Compare native/Lua codecs once per peer/case before stress sampling",
    )
    parser.add_argument(
        "--heap-check",
        action="store_true",
        help="Enable heap evidence for stress runs; changes performance measurements",
    )
    parser.add_argument(
        "--moving-use", action="store_true", help="Move with the native stick during the use press"
    )
    parser.add_argument(
        "--coins", type=int, default=0, help="Grant holder coins for payment prerequisites"
    )
    parser.add_argument(
        "--wall-use", action="store_true", help="Use beside an empty allowed door slot"
    )
    parser.add_argument(
        "--protect-use", action="store_true", help="Prevent incidental damage before the use probe"
    )
    parser.add_argument(
        "--end-tick", type=int, help="Extend observation after transitions (150 through 3600)"
    )
    parser.add_argument("--use-tick", type=int, default=60, help="Tick at which to press use")
    parser.add_argument(
        "--hold-ticks",
        type=int,
        default=6,
        help="Keep the native use button held for this many ticks",
    )
    parser.add_argument(
        "--continue-after-failure",
        action="store_true",
        help="Preserve a failed case, then resume remaining cases in recovered processes",
    )
    args = parser.parse_args()
    output = args.output.resolve()
    try:
        labs = validate_labs([args.host, args.client], output)
        validate_startup(labs)
        if args.mode == "stress":
            cases = stress_cases(json.loads(args.catalog.read_text()), args.case)
        elif args.mode in ("sweep", "effects"):
            catalog = json.loads(args.catalog.read_text())
            if args.mode == "effects":
                catalog["items"] = [
                    item for item in catalog["items"] if item.get("enum") in SUPPORTED_EFFECTS
                ]
            cases = select_cases(
                catalog,
                args.case,
                args.context or ("host-same", "client-split"),
            )
        else:
            item = {
                "key": "collectible:625" if args.mode == "mega" else "collectible:1",
                "kind": "collectible",
                "id": 625 if args.mode == "mega" else 1,
            }
            cases = select_cases(
                {"items": [item]},
                contexts=args.context
                or (
                    ("host-same", "client-same", "host-split", "client-split")
                    if args.mode == "mega"
                    else ("host-same",)
                ),
            )
            if args.mode == "mega":
                for case in cases:
                    case["physical"] = True
        if not 1 <= args.port < 65535 or not 10 <= args.timeout <= 86400:
            raise ValueError("Invalid port or timeout")
        if not 0 <= args.coins <= 99:
            raise ValueError("Coins must be between 0 and 99")
        if args.end_tick is not None and not 150 <= args.end_tick <= 3600:
            raise ValueError("End tick must be between 150 and 3600")
        if not 1 <= args.hold_ticks <= 300:
            raise ValueError("Use hold duration must be between 1 and 300 ticks")
        if not 60 <= args.use_tick < (args.end_tick or 150):
            raise ValueError("Use tick must be at least 60 and before the observation end")
        for case in cases:
            if args.moving_use:
                case["moving_use"] = True
            if args.coins:
                case["coins"] = args.coins
            if args.wall_use:
                case["wall_use"] = True
            if args.protect_use:
                case["protect_use"] = True
            if args.end_tick is not None:
                case["end_tick"] = args.end_tick
            if args.hold_ticks != 6:
                case["hold_ticks"] = args.hold_ticks
            if args.use_tick != 60:
                case["use_tick"] = args.use_tick
        if not 0 <= args.shard < args.shards or args.mode == "stress" and args.shards != 1:
            raise ValueError("Invalid shard; stress runs must remain exclusive")
        cases = cases[args.shard :: args.shards]
        if not cases:
            raise ValueError("No selected cases")
        idle(labs)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    output.mkdir(parents=True, exist_ok=False)
    validator = ROOT / "tools/item_effect_checks.py"
    shutil.copy2(validator, output / validator.name)
    recipes = ROOT / "tools/item_consumable_recipes.py"
    shutil.copy2(recipes, output / recipes.name)
    audit_contract = ROOT / "tools/item_audit.py"
    shutil.copy2(audit_contract, output / audit_contract.name)
    room_effects = ROOT / "tools/item_room_effects.py"
    shutil.copy2(room_effects, output / room_effects.name)
    damage_effects = ROOT / "tools/item_damage_effects.py"
    shutil.copy2(damage_effects, output / damage_effects.name)
    familiar_effects = ROOT / "tools/item_familiar_effects.py"
    shutil.copy2(familiar_effects, output / familiar_effects.name)
    manifest = {
        "commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "dll_sha256": hashlib.sha256((args.build / "isaac_lan_probe.dll").read_bytes()).hexdigest(),
        "loader_sha256": hashlib.sha256((args.build / "winmm.dll").read_bytes()).hexdigest(),
        "validator_sha256": hashlib.sha256(validator.read_bytes()).hexdigest(),
        "recipes_sha256": hashlib.sha256(recipes.read_bytes()).hexdigest(),
        "audit_sha256": hashlib.sha256(audit_contract.read_bytes()).hexdigest(),
        "room_effects_sha256": hashlib.sha256(room_effects.read_bytes()).hexdigest(),
        "damage_effects_sha256": hashlib.sha256(damage_effects.read_bytes()).hexdigest(),
        "familiar_effects_sha256": hashlib.sha256(familiar_effects.read_bytes()).hexdigest(),
        "cases": cases,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    pending, results, batches = cases, [], []
    summary = {"restored": True, "engine_pass": True, "results": [], "batches": batches}
    while pending:
        name = f"batch-{len(batches) + 1:03d}"
        report = run_batch(args, pending, output / name, labs)
        values = report.get("results", [])
        started = [i for i, value in enumerate(values) if value["status"] != "untested"]
        consumed = max(started) + 1 if started else 0
        results.extend(values[:consumed])
        remaining = pending[consumed:]
        batches.append(
            {
                "name": name,
                "engine_pass": report.get("engine", {}).get("pass", False),
                "restored": report["restored"],
                "restart_reason": report.get("watchdog") or report.get("engine", {}).get("error"),
            }
        )
        summary["restored"] &= report["restored"]
        summary["engine_pass"] &= batches[-1]["engine_pass"]
        summary["results"] = results + [
            {**case, "status": "untested", "compatibility_verified": False} for case in remaining
        ]
        (output / "summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2) + "\n"
        )
        if (
            not report["restored"]
            or not consumed
            or not args.continue_after_failure
            or not remaining
        ):
            break
        if batches[-1]["engine_pass"]:
            raise RuntimeError("Completion banner did not cover all planned cases")
        pending = remaining
    print(
        json.dumps(
            {
                "output": str(output),
                "restored": summary["restored"],
                "engine_pass": summary["engine_pass"],
            }
        ),
        flush=True,
    )
    return 0 if summary["restored"] and summary["engine_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
