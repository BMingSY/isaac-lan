#!/usr/bin/env python3
"""Import measured audit results without promoting smoke checks to compatibility."""

import argparse
import json
from pathlib import Path

from item_audit import ROOT, events, summarize_case

RANK = {"untested": 0, "basic_pass": 1, "incomplete": 2, "problem": 3, "crash": 4}


def measured_stress(result, evidence):
    observed, metrics = {}, {}
    for role, values in result["observations"].items():
        samples = [value for value in values if value["event"] == "sample" and value["tick"] >= 150]
        actor = result["slot"]
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
    reached = all(
        observed.get("host", {}).get(field, {}).get("min", 0) >= result.get(field, 0) * 0.9
        for field in ("tears", "projectiles")
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
                        dict.fromkeys(old.get("previous_evidence", []) + [old["evidence"]])
                    )
                    findings["stress"].remove(old)
                findings["stress"].append(value)
                continue
            item = findings["audit"].setdefault(
                case.get("item", f"{case['kind']}:{case['id']}"),
                {"status": "untested", "checks": []},
            )
            if RANK[result["status"]] > RANK[item["status"]]:
                item["status"] = result["status"]
            check = {
                "case": case["key"],
                "status": result["status"],
                "unconfirmed": result["unconfirmed_checks"],
                "problems": result["problems"],
                "evidence": evidence,
            }
            for field in ("process_exit", "interruption"):
                if field in result:
                    check[field] = result[field]
            if check not in item["checks"]:
                item["checks"].append(check)
            if item["status"] == "crash":
                item["impact"] = (
                    "实机扫描触发访问异常／进程崩溃；具体持有者、房间条件见该项验证记录。尚未修复。"
                )
            elif item["status"] == "problem":
                categories = {
                    problem["category"] for entry in item["checks"] for problem in entry["problems"]
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
