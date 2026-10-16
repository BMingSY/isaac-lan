#!/usr/bin/env python3
"""Import measured audit results without promoting smoke checks to compatibility."""

import argparse
import json
from pathlib import Path

from item_audit import ROOT, events, summarize_case

RANK = {"untested": 0, "basic_pass": 1, "incomplete": 2, "problem": 3, "crash": 4}


def measured_stress(result, evidence):
    observed, metrics, sample_counts = {}, {}, {}
    for role, values in result["observations"].items():
        samples = [value for value in values if value["event"] == "sample" and value["tick"] >= 150]
        actor = result["slot"]
        sample_counts[role] = len(samples)
        observed[role] = {
            field: {
                "min": min(
                    (sample["players"][actor].get(field, 0) for sample in samples), default=0
                ),
                "max": max(
                    (sample["players"][actor].get(field, 0) for sample in samples), default=0
                ),
            }
            for field in ("item_count", "tears", "projectiles")
        }
        metrics[role] = next((value for value in values if value["event"] == "metrics"), {})
    requested = {
        "item_count": len(result.get("loadout", [])) + result.get("copies", 0),
        "tears": result.get("tears", 0),
        "projectiles": result.get("projectiles", 0),
    }
    reached = all(
        sample_counts.get(role, 0) >= 2
        and all(
            observed.get(role, {}).get(field, {}).get("min", 0) >= count * 0.9
            for field, count in requested.items()
        )
        for role in ("host", "client")
    )
    return {
        "case": result["key"],
        "status": result["status"],
        "requested": {
            "distinct": len(result.get("loadout", [])),
            "copies": result.get("copies", 0),
            "tears": result.get("tears", 0),
            "projectiles": result.get("projectiles", 0),
        },
        "load_reached": reached,
        "observed": observed,
        "metrics": metrics,
        "evidence": evidence,
    }


def import_run(findings, directory):
    excluded = next(
        (
            entry
            for entry in findings.get("excluded_runs", [])
            if entry["evidence"] == directory.name
        ),
        None,
    )
    if excluded:
        raise ValueError(f"Excluded run {directory.name}: {excluded['reason']}")
    manifest = json.loads((directory / "manifest.json").read_text())
    if manifest["dll_sha256"] != findings["dll_sha256"]:
        raise ValueError("Do not combine different native candidates")
    for batch in sorted(directory.glob("batch-*")):
        report_path = batch / "report.json"
        if not report_path.is_file():
            continue
        report = json.loads(report_path.read_text())
        peers = {}
        for role in ("host", "client"):
            path = batch / (role + "-events.log")
            if not path.is_file():
                path = batch / "engine" / role / "log.txt"
            peers[role] = events(path.read_text(errors="replace")) if path.is_file() else []
        for case in report["cases"]:
            result = summarize_case(case, peers, report.get("engine"))
            if result["status"] == "untested":
                continue
            evidence = directory.name + "/" + batch.name
            if case["kind"] == "stress":
                value = measured_stress(result, evidence)
                old = next(
                    (entry for entry in findings["stress"] if entry["case"] == case["key"]), None
                )
                if old:
                    value["previous_evidence"] = list(
                        dict.fromkeys(
                            entry
                            for entry in old.get("previous_evidence", []) + [old["evidence"]]
                            if entry != evidence
                        )
                    )
                    findings["stress"].remove(old)
                findings["stress"].append(value)
                continue
            item = findings["audit"].setdefault(
                case.get("item", f"{case['kind']}:{case['id']}"),
                {"status": "untested", "checks": []},
            )
            check = {
                "case": case["key"],
                "status": result["status"],
                "unconfirmed": result["unconfirmed_checks"],
                "problems": result["problems"],
                "evidence": evidence,
                "conditions": {
                    key: case[key]
                    for key in ("moving_use", "coins", "wall_use", "end_tick")
                    if key in case
                },
            }
            for field in (
                "process_exit",
                "crash_phase",
                "interruption",
                "interruption_phase",
                "teardown_events",
            ):
                if field in result:
                    check[field] = result[field]
            review = next(
                (
                    entry
                    for entry in findings.get("excluded_checks", [])
                    if entry["case"] == case["key"] and entry["evidence"] == evidence
                ),
                None,
            )
            if review:
                if not review.get("reason"):
                    raise ValueError("An excluded observation requires a reviewed reason")
                check["excluded_reason"] = review["reason"]
            item["checks"] = [
                entry
                for entry in item["checks"]
                if (entry["case"], entry["evidence"]) != (check["case"], evidence)
            ] + [check]
            item["status"] = max(
                (entry["status"] for entry in item["checks"] if not entry.get("excluded_reason")),
                key=RANK.get,
                default="untested",
            )
            if item["status"] == "crash":
                item["impact"] = (
                    "实机扫描触发访问异常／进程崩溃；具体持有者、房间条件见该项验证记录。尚未修复。"
                )
            elif item["status"] == "problem":
                categories = {
                    problem["category"]
                    for entry in item["checks"]
                    if not entry.get("excluded_reason")
                    for problem in entry["problems"]
                }
                labels = {
                    "no_effect": "未观察到应有的直接属性效果",
                    "non_native": "双端属性／背包不同或客机重复执行效果",
                    "reconnect": "客机断开／重连",
                    "incomplete": "场景未按时完成",
                }
                item["impact"] = (
                    "；".join(labels.get(category, category) for category in sorted(categories))
                    + "，需专项确认归因。"
                )
            elif item["status"] == "incomplete":
                item["impact"] = "基础流程未完整确认；条件效果或使用入口需要专项验证。"
            elif item["status"] == "untested":
                item["impact"] = "现有记录因夹具问题排除；效果需要重新验证。"
            else:
                item["impact"] = "本轮基础场景未发现异常；条件效果与组合尚未穷举。"
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path, nargs="+")
    args = parser.parse_args()
    path = ROOT / "tests/fixtures/item_audit_findings.json"
    findings = json.loads(path.read_text())
    for report in args.reports:
        import_run(findings, report)
    path.write_text(json.dumps(findings, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
