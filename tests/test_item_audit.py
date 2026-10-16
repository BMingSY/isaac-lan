import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from item_audit import catalog_from_log, events, select_cases, summarize_case
from run_item_audit import validate_labs, validate_startup


def test_pill_zero_and_horse_variants_are_not_lost_or_used_as_entity_subtypes():
    catalog = {"items": [{"kind": "pill", "id": 0, "key": "pill:0", "entity_subtype": "color"}]}
    cases = select_cases(catalog)
    assert len(cases) == 4
    assert {case["horse"] for case in cases} == {False, True}
    assert {case["slot"] for case in cases} == {0, 1}
    assert all(case["id"] == 0 for case in cases)
    assert all(case["physical"] for case in cases)


def test_partial_or_one_sided_run_never_becomes_verified_compatibility():
    case = {"key": "collectible:625/host-same"}
    begin = {"event": "case_begin", "key": case["key"]}
    end = {"event": "case_end", "key": case["key"]}
    assert summarize_case(case, {"host": [begin, end], "client": []})["status"] == "incomplete"
    result = summarize_case(case, {"host": [begin, end], "client": [begin, end]})
    assert result["status"] == "incomplete"
    assert not result["compatibility_verified"]


def test_complete_native_smoke_still_does_not_prove_conditional_effects():
    case = {"key": "card:1/host-same", "physical": True}

    def event(name, **values):
        return {"event": name, "key": case["key"], **values}

    samples = [event("sample", tick=tick, players=[]) for tick in (90, 120)]
    values = [
        event(name) for name in ("case_begin", "give_end", "use_return", "use_callback", "case_end")
    ] + samples
    result = summarize_case(case, {"host": values, "client": [event("case_end"), *samples]})
    assert result["status"] == "basic_pass"
    assert not result["compatibility_verified"]
    values = [value for value in values if value["event"] != "use_callback"]
    assert (
        summarize_case(case, {"host": values, "client": [event("case_end"), *samples]})["status"]
        == "incomplete"
    )


def test_repeated_attribute_divergence_is_reported_even_after_clean_exit():
    case = {"key": "collectible:7/host-same"}
    host = [
        {
            "event": "sample",
            "key": case["key"],
            "label": "observe",
            "tick": tick,
            "players": [{"slot": 0, "damage": 4.5}],
        }
        for tick in (90, 120)
    ]
    client = [{**event, "players": [{"slot": 0, "damage": 3.5}]} for event in host]
    host.insert(0, {"event": "case_begin", "key": case["key"]})
    host.insert(1, {"event": "give_begin", "key": case["key"]})
    result = summarize_case(case, {"host": host, "client": client})
    assert result["status"] == "problem"
    assert result["problems"][0]["category"] == "non_native"
    # A temporary stat may change between pre-update observation and capture.
    # The actual snapshot boundary is the relevant peer comparison.
    host += [{**event, "label": "captured"} for event in client]
    assert not summarize_case(case, {"host": host, "client": client})["problems"]


def test_crash_is_distinct_from_forced_cleanup_and_unstarted_cases():
    case = {"key": "card:1/client-split"}
    peers = {"host": [{"event": name, "key": case["key"]} for name in ("case_begin", "give_begin")]}
    result = {"process_exit": {"host": {"exit_code": 0xC0000005}}}
    assert summarize_case(case, peers, result)["status"] == "crash"
    assert summarize_case({"key": "card:2/client-split"}, peers, result)["status"] == "untested"
    result["process_exit"]["host"]["exit_code"] = 0xFFFFFFFF
    assert summarize_case(case, peers, result)["status"] == "incomplete"
    result["process_exit"]["host"]["exit_code"] = -1
    assert summarize_case(case, peers, result)["status"] == "incomplete"
    result["process_exit"]["host"]["exit_code"] = 0xC0000005
    peers["host"].append({"event": "case_begin", "key": "card:2/client-split"})
    assert summarize_case(case, peers, result)["status"] == "incomplete"


def test_setup_crash_is_incomplete_and_cleanup_crash_is_not_a_pass():
    case = {"key": "card:1/host-same"}
    begin = {"event": "case_begin", "key": case["key"]}
    end = {"event": "case_end", "key": case["key"]}
    engine = {"process_exit": {"client": {"exit_code": 0xC0000005}}}
    result = summarize_case(case, {"host": [begin], "client": []}, engine)
    assert result["status"] == "incomplete"
    assert result["crash_phase"] == "setup"
    peers = {
        "host": [begin, {"event": "give_begin", "key": case["key"]}, end],
        "client": [begin, end],
    }
    result = summarize_case(case, peers, engine)
    assert result["status"] == "crash"
    assert result["crash_phase"] == "cleanup"


def test_failed_fixture_prerequisite_is_not_an_item_reconnect_bug():
    case = {"key": "collectible:580/client-split"}
    host = [
        {"key": case["key"], "event": "case_begin"},
        {
            "key": case["key"],
            "event": "problem",
            "category": "reconnect",
            "detail": "fixture error",
        },
    ]
    result = summarize_case(case, {"host": host, "client": []})
    assert result["status"] == "incomplete"
    assert result["interruption_phase"] == "setup"
    assert "fixture_setup" in result["unconfirmed_checks"]


def test_full_registry_and_shards_cover_each_entry_and_pill_variant_once():
    from collections import Counter

    catalog = json.loads((ROOT / "tests/fixtures/item_catalog.json").read_text())
    cases = select_cases(catalog)
    assert len({item["key"] for item in catalog["items"]}) == len(catalog["items"])
    assert len({case["key"] for case in cases}) == len(cases)
    count = Counter(case["item"] for case in cases)
    assert all(
        count[item["key"]] == (4 if item["kind"] == "pill" else 2) for item in catalog["items"]
    )
    shards = [cases[index::3] for index in range(3)]
    assert Counter(case["key"] for shard in shards for case in shard) == Counter(
        case["key"] for case in cases
    )
    assert all(
        item["entity_subtype"] == "color" for item in catalog["items"] if item["kind"] == "pill"
    )


def test_basic_pass_does_not_erase_a_known_unresolved_crash():
    from render_item_compatibility import conclusion

    value = conclusion(
        {"status": "reported", "impact": "random crash unresolved"},
        {"status": "basic_pass", "impact": "smoke completed"},
    )
    assert value["status"] == "reported"
    assert value["impact"] == "random crash unresolved"
    value = conclusion(
        {"status": "reported", "impact": "user report"},
        {"status": "crash", "impact": "native crash reproduced"},
    )
    assert value["status"] == "crash"
    assert value["impact"] == "native crash reproduced"


def test_truncated_catalog_and_torn_event_are_not_accepted():
    assert events('LAN_ITEM_AUDIT {"event":') == []
    text = "LAN_ITEM_AUDIT " + json.dumps({"event": "catalog", "item": {"key": "pill:0"}})
    with pytest.raises(ValueError, match="truncated"):
        catalog_from_log(text)


def test_known_problem_is_not_overridden_by_later_completion():
    case = {"key": "pill:0/host-same"}
    values = [
        {"key": case["key"], "event": "case_begin"},
        {"key": case["key"], "event": "give_begin"},
        {"key": case["key"], "event": "case_end"},
        {"key": case["key"], "event": "problem", "category": "reconnect"},
    ]
    assert summarize_case(case, {"host": values, "client": values})["status"] == "problem"


def test_client_errors_after_host_crash_do_not_consume_the_next_item():
    case = {"key": "pill:1/host-same"}
    peers = {
        "host": [{"event": "case_begin", "key": "card:97/host-same"}],
        "client": [{"event": "problem", "key": case["key"], "category": "reconnect"}],
    }
    assert summarize_case(case, peers)["status"] == "untested"


def test_fixture_exit_socket_close_is_not_misattributed_to_item_reconnect():
    case = {"key": "collectible:171/host-same"}

    def event(name, **values):
        return {"event": name, "key": case["key"], **values}

    host = [
        event("case_begin"),
        event("give_begin"),
        event("exit_requested", now_ms=100),
        event("case_end"),
    ]
    client = [
        event("case_begin"),
        event("problem", category="reconnect", now_ms=101),
        event("case_aborted"),
    ]
    result = summarize_case(case, {"host": host, "client": client})
    assert result["status"] == "incomplete"
    assert not result["problems"]
    assert result["teardown_events"]
    assert "client_case_end" in result["unconfirmed_checks"]
    client[1]["now_ms"] = 99
    assert summarize_case(case, {"host": host, "client": client})["status"] == "problem"


def test_manual_lab_alias_is_refused(tmp_path):
    manual = tmp_path / "host-001"
    manual.mkdir()
    alias = tmp_path / "alias"
    alias.symlink_to(manual, target_is_directory=True)
    with pytest.raises(ValueError, match="manual"):
        validate_labs([alias, tmp_path / "client"], tmp_path / "evidence")


def test_first_start_notice_must_be_cleared_before_native_audit(tmp_path):
    options = tmp_path / "profile/Documents/My Games/Binding of Isaac Repentance+/options.ini"
    options.parent.mkdir(parents=True)
    options.write_text("[Options]\nEnableMods=1\n")
    with pytest.raises(ValueError, match="first-start Beta notice"):
        validate_startup([tmp_path])
    options.write_text("[Options]\nAcceptedPublicBeta_v1.9.7.17=1\n")
    validate_startup([tmp_path])


def test_import_preserves_failures_and_requires_explicit_review_to_exclude(tmp_path):
    from import_item_audit import import_run

    case = {
        "key": "collectible:1/host-same",
        "item": "collectible:1",
        "kind": "collectible",
        "id": 1,
    }

    def make_report(name, problem=False):
        directory = tmp_path / name
        batch = directory / "batch-001"
        batch.mkdir(parents=True)
        (directory / "manifest.json").write_text(json.dumps({"dll_sha256": "candidate"}))
        (batch / "report.json").write_text(json.dumps({"cases": [case], "engine": {}}))
        values = [
            {"event": event, "key": case["key"]}
            for event in ("case_begin", "give_end", "use_return", "case_end")
        ]
        values += [
            {"event": "sample", "key": case["key"], "tick": tick, "players": []}
            for tick in (90, 120)
        ]
        if problem:
            values.append({"event": "problem", "key": case["key"], "category": "non_native"})
        for role in ("host", "client"):
            (batch / (role + "-events.log")).write_text(
                "\n".join("LAN_ITEM_AUDIT " + json.dumps(v) for v in values)
            )
        return directory

    failed, passed = make_report("failed", True), make_report("passed")
    findings = {"dll_sha256": "candidate", "audit": {}, "stress": []}
    import_run(findings, failed)
    import_run(findings, failed)
    item = findings["audit"][case["item"]]
    assert len(item["checks"]) == 1
    import_run(findings, passed)
    assert item["status"] == "problem"
    findings["excluded_checks"] = [
        {
            "case": case["key"],
            "evidence": "failed/batch-001",
            "reason": "Confirmed fixture failure; original evidence retained",
        }
    ]
    import_run(findings, failed)
    assert item["status"] == "basic_pass"
    assert len(item["checks"]) == 2
    assert any(
        entry["status"] == "problem" and entry.get("excluded_reason") for entry in item["checks"]
    )


def test_excluded_run_cannot_be_reimported_as_valid_coverage(tmp_path):
    from import_item_audit import import_run

    findings = {
        "excluded_runs": [{"evidence": "obscured", "reason": "Startup notice hid gameplay"}]
    }
    with pytest.raises(ValueError, match="Startup notice hid gameplay"):
        import_run(findings, tmp_path / "obscured")


def test_direct_effect_requires_observed_change_and_tolerates_missing_actor():
    case = {"key": "pill:6/host-same", "kind": "pill", "slot": 0, "enum": "PILLEFFECT_HEALTH_UP"}

    def sample(label, tick, player):
        return {
            "event": "sample",
            "key": case["key"],
            "label": label,
            "tick": tick,
            "players": [player],
        }

    before = sample("before", 30, {"slot": 0, "max_hearts": 8})
    use = {"event": "use_callback", "key": case["key"]}
    unchanged = sample("observe", 90, {"slot": 0, "max_hearts": 8})
    result = summarize_case(case, {"host": [before, use, unchanged]})
    assert any(p["category"] == "no_effect" for p in result["problems"])
    changed = sample("observe", 90, {"slot": 0, "max_hearts": 10})
    assert not summarize_case(case, {"host": [before, use, changed]})["problems"]
    missing = sample("observe", 90, {"slot": 0, "missing": True})
    assert not summarize_case(case, {"host": [before, use, missing]})["problems"]


def test_requested_projectile_count_does_not_substitute_for_actual_stress_load():
    from import_item_audit import measured_stress

    result = {
        "slot": 0,
        "key": "stress:tears-2000",
        "status": "incomplete",
        "tears": 2000,
        "observations": {
            "host": [
                {
                    "event": "sample",
                    "tick": 150,
                    "players": [{"item_count": 0, "tears": 512, "projectiles": 0}],
                }
            ]
        },
    }
    measured = measured_stress(result, "capacity-test")
    assert not measured["load_reached"]
    assert measured["observed"]["host"]["tears"]["max"] == 512
