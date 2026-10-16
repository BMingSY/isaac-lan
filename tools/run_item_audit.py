#!/usr/bin/env python3
"""Audit collectibles, trinkets, cards and pills in two protected native processes."""

import argparse
import configparser
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
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
)
from lab_profile import ProtectedLabs, idle, windows


def validate_startup(labs):
    for lab in labs:
        options = configparser.ConfigParser()
        options.read(lab / "profile/Documents/My Games/Binding of Isaac Repentance+/options.ini")
        if options.get("Options", "AcceptedPublicBeta_v1.9.7.17", fallback="0") != "1":
            raise ValueError(
                f"{lab.name}: finish the native first-start Beta notice before auditing; "
                "background Lua progress does not prove the gameplay view is visible"
            )


def validate_labs(values, output):
    labs = [Path(value).resolve() for value in values]
    if len(labs) != 2 or len(set(labs)) != 2:
        raise ValueError("Two distinct owned labs are required")
    for lab in labs:
        if lab.name.casefold() in {"host-001", "client-001"}:
            raise ValueError("The user's manual games must not be controlled")
        if not (lab / ".isaac-lan-lab").is_file() or not (lab / "game/isaac-ng.exe").is_file():
            raise ValueError("Every lab needs an ownership marker and its own executable")
        if output.is_relative_to(lab) or lab.is_relative_to(output):
            raise ValueError("Evidence must be outside the protected labs")
    return labs


def run_batch(args, cases, output, labs):
    output.mkdir(parents=True, exist_ok=False)
    script = output / "fixture.lua"
    journals = {role: output / (role + "-events.log") for role in ("host", "client")}
    build_fixture(
        script,
        {"cases": cases, "journal": {role: windows(path) for role, path in journals.items()}},
    )
    subprocess.run([shutil.which("luac5.3") or "luac", "-p", str(script)], check=True)
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
        "--automatic",
        "--menu-start",
        "--virtual-input",
        "--menu-port",
        str(args.port),
        "--heap-check",
        "--scenario-timeout",
        str(args.timeout),
    ]
    if args.record:
        command.extend(("--native-record-both", "--frame-ms", "1000"))
    if args.mode == "stress":
        command.append("--performance")
    protected = ProtectedLabs(labs, output)
    report = {
        "cases": cases,
        "command": command,
        "fixture_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
        "restored": False,
    }
    (output / "backup.json").write_text(json.dumps(protected.report(), indent=2) + "\n")
    try:
        with (output / "engine.log").open("w") as stream:
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
            last_progress, last_event, offset = time.monotonic(), None, 0
            try:
                while process.poll() is None:
                    path = journals["host"]
                    text = ""
                    if path.exists():
                        with path.open("rb") as journal:
                            journal.seek(offset)
                            chunk = journal.read()
                        complete = chunk.rfind(b"\n") + 1
                        offset += complete
                        text = chunk[:complete].decode(errors="replace")
                    records = events(text)
                    if records:
                        last_event, last_progress = records[-1], time.monotonic()
                        for marker in records:
                            if marker["event"] in {"case_begin", "problem", "case_end"}:
                                print(json.dumps(marker, ensure_ascii=False), flush=True)
                    if last_event and time.monotonic() - last_progress > 90:
                        report["watchdog"] = (
                            "No audit progress for 90 seconds; preserve the interrupted case"
                        )
                        process.terminate()
                        break
                    time.sleep(0.5)
                process.wait(timeout=120)
            except BaseException:
                process.terminate()
                process.wait(timeout=120)
                raise
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
    finally:
        try:
            report["restoration"] = protected.restore()
            report["restored"] = True
        except Exception as error:
            report["restoration_error"] = str(error)
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=("catalog", "mega", "sweep", "stress"), default="mega")
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
        elif args.mode == "sweep":
            cases = select_cases(
                json.loads(args.catalog.read_text()),
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
        if not 0 <= args.shard < args.shards or args.mode == "stress" and args.shards != 1:
            raise ValueError("Invalid shard; stress runs must remain exclusive")
        cases = cases[args.shard :: args.shards]
        if not cases:
            raise ValueError("No selected cases")
        idle(labs)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    output.mkdir(parents=True, exist_ok=False)
    manifest = {
        "commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "dll_sha256": hashlib.sha256((args.build / "isaac_lan_probe.dll").read_bytes()).hexdigest(),
        "loader_sha256": hashlib.sha256((args.build / "winmm.dll").read_bytes()).hexdigest(),
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
