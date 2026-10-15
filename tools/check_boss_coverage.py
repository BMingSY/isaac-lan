#!/usr/bin/env python3
"""Combine successful native arena, ending and Greed reports into Boss coverage."""

import argparse
import json
from pathlib import Path

from build_boss_suite import catalog


def summarize(arena_reports, ending_reports, special_reports, partial_reports=()):
    arenas, routes, rejected = set(), set(), []
    for kind, reports in (
        ("arena", arena_reports),
        ("ending", ending_reports),
        ("special", special_reports),
    ):
        for index, report in enumerate(reports):
            if not report.get("passed") or not report.get("restored"):
                rejected.append({"kind": kind, "index": index})
                continue
            if kind == "arena":
                peers = report.get("peers", {})
                if all(peers.get(role, {}).get("passed") for role in ("host", "client")):
                    arenas.update(set(peers["host"]["cases"]) & set(peers["client"]["cases"]))
            elif kind == "ending":
                for name, peers in report.get("routes", {}).items():
                    if all(
                        all(
                            peers.get(role, {}).get(flag) for flag in ("win", "cleanup", "progress")
                        )
                        and not peers[role].get("missing_alternate_floors", [])
                        for role in ("host", "client")
                    ):
                        routes.add(name)
            else:
                for name, peers in report.get("cases", {}).items():
                    if all(peers.get(role, {}).get("passed") for role in ("host", "client")):
                        routes.add(name)
    partial = []
    for index, report in enumerate(partial_reports):
        if not report.get("restored") or not report.get("interrupted_cleanly"):
            rejected.append({"kind": "partial-arena", "index": index})
            continue
        peers = report.get("peers", {})
        accepted = set()
        for case in report.get("cases", []):
            key = case["key"]
            if all(
                key not in peers.get(role, {}).get("duplicates", [])
                and peers.get(role, {}).get("cases", {}).get(key, {}).get("live", 0) >= 30
                and peers[role]["cases"][key].get("visible", 0) >= 10
                and (role == "host" or peers[role]["cases"][key].get("views", 0) >= 30)
                for role in ("host", "client")
            ):
                accepted.add(key)
        arenas.update(accepted)
        partial.append({"index": index, "completed_cases": sorted(accepted)})
    data = catalog()
    missing_arena = [case["key"] for case in data["arena"] if case["key"] not in arenas]
    missing_routes = [
        {"boss_id": case["boss_id"], "name": case["name"], "route": case["route"]}
        for case in data["ending_routes"]
        if case["route"] not in routes
    ]
    return {
        "passed": not (missing_arena or missing_routes or rejected),
        "arena_passed": len(data["arena"]) - len(missing_arena),
        "arena_total": len(data["arena"]),
        "route_bosses_passed": len(data["ending_routes"]) - len(missing_routes),
        "route_bosses_total": len(data["ending_routes"]),
        "missing_arena": missing_arena,
        "missing_route_bosses": missing_routes,
        "rejected_reports": rejected,
        "interrupted_arena_reports": partial,
        "unavailable": data["unavailable"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for kind in ("arena", "ending", "special"):
        parser.add_argument("--" + kind, type=Path, action="append", default=[])
    parser.add_argument(
        "--partial-arena",
        type=Path,
        action="append",
        default=[],
        help="Retain completed cases from a deliberately interrupted, cleanly closed arena run",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    partial = []
    from run_bosses import evidence

    for path in args.partial_arena:
        value = json.loads(path.read_text())
        engine = json.loads((path.parent / "engine/result.json").read_text())
        value["interrupted_cleanly"] = (
            engine.get("clean_exit") is True
            and engine.get("error") == "Test interrupted by signal 15"
        )
        # Re-read the archived per-case assertions, including duplicate markers.
        value["peers"] = {
            role: evidence(
                (path.parent / "engine" / role / "log.txt").read_text(errors="replace"),
                value["cases"],
            )
            for role in ("host", "client")
        }
        partial.append(value)
    report = summarize(
        *[
            [json.loads(path.read_text()) for path in getattr(args, kind)]
            for kind in ("arena", "ending", "special")
        ],
        partial_reports=partial,
    )
    report["inputs"] = {
        kind: [str(path) for path in getattr(args, kind)]
        for kind in ("arena", "ending", "special", "partial_arena")
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {key: value for key, value in report.items() if key != "inputs"},
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
