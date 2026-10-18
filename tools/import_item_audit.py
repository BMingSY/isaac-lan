#!/usr/bin/env python3
"""Import measured audit results without promoting smoke checks to compatibility."""

import argparse
import json
from pathlib import Path

from item_audit import AuditJournals, ROOT, summarize_case

RANK = {"untested": 0, "basic_pass": 1, "verified": 1, "incomplete": 2, "problem": 3, "crash": 4}


def start_candidate(findings, manifest):
    """Keep the old measurements, with their build identity, when fixing bugs."""
    old = findings["dll_sha256"]
    candidates = findings.setdefault("candidates", {})
    candidates.setdefault(old, {"commit": findings.get("candidate")})
    for item in findings["audit"].values():
        for check in item["checks"]:
            check.setdefault("dll_sha256", old)
    for check in findings["stress"]:
        check.setdefault("dll_sha256", old)
    current = manifest["dll_sha256"]
    candidates[current] = {
        key: manifest[key] for key in ("commit", "loader_sha256") if key in manifest
    }
    findings["dll_sha256"] = current
    findings["candidate"] = manifest.get("commit")


def item_status(key, checks):
    failures = [check for check in checks if check["status"] in ("problem", "crash")]
    if failures:
        return max((check["status"] for check in failures), key=RANK.get)
    # A completed rerun can fill missing evidence, but never erase a failure.
    latest = {check["case"]: check for check in checks}
    state = max((check["status"] for check in latest.values()), key=RANK.get, default="untested")
    if state == "incomplete":
        return state
    # One holder passing cannot certify an item. Pills also need both sizes.
    required = {
        key + "/" + context + suffix
        for context in ("host-same", "client-split")
        for suffix in (("", "/horse") if key.startswith("pill:") else ("",))
    }
    if any(check.get("conditions", {}).get("pocket_effect") for check in checks):
        required |= {case + "/occupied" for case in list(required)}
    verified = {check["case"] for check in latest.values() if check["status"] == "verified"}
    return "verified" if required <= verified else "basic_pass" if checks else "untested"


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
        "problems": result.get("problems", []),
        "unconfirmed": result.get("unconfirmed_checks", []),
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
        # New runs freeze their validator and results. Reimporting evidence
        # after a recipe correction must not silently rewrite the old failure.
        frozen = {r["key"]: r for r in report.get("results", [])}
        journals = {}
        for role in ("host", "client"):
            path = batch / (role + "-events.log")
            if not path.is_file():
                path = batch / "engine" / role / "log.txt"
            journals[role] = path
        evidence_index = None

        def observations(key):
            nonlocal evidence_index
            if evidence_index is None:
                evidence_index = AuditJournals(journals)
                expected = report.get("journal_sha256")
                if expected is not None and evidence_index.sha256 != expected:
                    raise ValueError("Audit journals differ from the frozen report")
            return evidence_index.observations(key)

        for case in report["cases"]:
            if manifest.get("validator_sha256"):
                if case["key"] not in frozen:
                    raise ValueError("Frozen audit is missing a case result")
                result = frozen[case["key"]]
            else:
                peers = observations(case["key"])
                result = summarize_case(
                    case, peers, report.get("engine"), last_case_key=evidence_index.last_case_key
                )
            if result["status"] == "untested":
                continue
            evidence = directory.name + "/" + batch.name
            if case["kind"] == "stress":
                if "observations" not in result:
                    result = {**result, "observations": observations(case["key"])}
                value = measured_stress(result, evidence)
                value["dll_sha256"] = manifest["dll_sha256"]
                old = next(
                    (entry for entry in findings["stress"] if entry["case"] == case["key"]), None
                )
                if old:
                    if old["evidence"] != evidence:
                        findings.setdefault("previous_stress", []).append(old)
                    if old.get("dll_sha256") == manifest["dll_sha256"] and old["status"] in (
                        "problem",
                        "crash",
                    ):
                        value["latest_status"] = value["status"]
                        value["status"] = max((old["status"], value["status"]), key=RANK.get)
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
                "physical": bool(case.get("physical")),
                "dll_sha256": manifest["dll_sha256"],
                "effect_checks": result["effect_checks"],
                "use_evidence": result.get("use_evidence"),
                "conditions": {
                    key: case[key]
                    for key in (
                        "moving_use",
                        "coins",
                        "wall_use",
                        "protect_use",
                        "end_tick",
                        "hold_ticks",
                        "use_tick",
                        "pocket_effect",
                        "occupied_pocket",
                    )
                    if key in case
                },
            }
            for field in (
                "process_exit",
                "crash_phase",
                "interruption",
                "interruption_phase",
                "teardown_events",
                "preparation_events",
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
            current = [
                entry
                for entry in item["checks"]
                if not entry.get("excluded_reason")
                and entry.get("dll_sha256", findings["dll_sha256"]) == manifest["dll_sha256"]
            ]
            item["status"] = item_status(case.get("item", f"{case['kind']}:{case['id']}"), current)
            if item["status"] == "crash":
                item["impact"] = (
                    "实机扫描触发访问异常／进程崩溃；具体持有者、房间条件见该项验证记录。尚未修复。"
                )
            elif item["status"] == "problem":
                categories = {
                    problem["category"] for entry in current for problem in entry["problems"]
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
                item["impact"] = "效果证据不完整。"
            elif item["status"] == "untested":
                item["impact"] = "现有记录因夹具问题排除；效果需要重新验证。"
            else:
                item.pop("impact", None)
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path, nargs="+")
    parser.add_argument("--new-candidate", action="store_true")
    args = parser.parse_args()
    path = ROOT / "tests/fixtures/item_audit_findings.json"
    findings = json.loads(path.read_text())
    if args.new_candidate:
        start_candidate(findings, json.loads((args.reports[0] / "manifest.json").read_text()))
    for report in args.reports:
        import_run(findings, report)
    path.write_text(json.dumps(findings, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
