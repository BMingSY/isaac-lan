"""Release evidence must identify missing floors and Bosses, even after a win."""

from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from build_boss_suite import build, catalog, select_cases
from build_ending_suite import build as build_endings
from run_bosses import COMPLETION, evidence
from run_endings import route_evidence


def test_boss_shards_cover_each_playable_entry_once(tmp_path):
    data = catalog()
    ids = [case["boss_id"] for case in data["arena"] if "boss_id" in case]
    ids += [case["boss_id"] for case in data["ending_routes"]]
    assert len(ids) == len(set(ids))
    assert set(ids) == set(range(1, 104)) - {98, 103}
    shards = [select_cases(index, 3) for index in range(3)]
    keys = [case["key"] for shard in shards for case in shard]
    assert len(keys) == len(set(keys)) == len(data["arena"])
    assert set(keys) == {case["key"] for case in data["arena"]}
    for index, shard in enumerate(shards):
        assert build(tmp_path / f"boss-{index}.lua", index, 3) == shard
    with pytest.raises(ValueError):
        select_cases(3, 3)
    with pytest.raises(ValueError):
        select_cases(keys=[keys[0], keys[0]])


def test_boss_success_requires_every_unique_result():
    cases = select_cases(keys=["boss-1", "boss-82"])
    rows = [f"ALL_BOSSES PASS key={case['key']} live=120 visible=90 views=60" for case in cases]
    assert evidence("\n".join([COMPLETION, *rows]), cases)["passed"]
    assert not evidence("\n".join([COMPLETION, *rows[:1]]), cases)["passed"]
    assert not evidence("\n".join([COMPLETION, *rows, rows[0]]), cases)["passed"]
    assert not evidence("\n".join([COMPLETION, *rows]).replace("visible=90", "visible=0"), cases)[
        "passed"
    ]


def test_mother_win_does_not_hide_missing_alternate_floor():
    prefix = "LAN_NETWORK ENDINGS mother "
    rows = [prefix + f"ROUTE_FLOOR stage={stage} type=4" for stage in range(1, 7)]
    rows += [
        prefix + "NATIVE_WIN callback=MC_POST_GAME_END game_over=false",
        prefix + "PASS native ending and session cleanup",
        prefix + "LOCAL_PROGRESS_RESTORED",
    ]
    result = route_evidence("\n".join(rows), "mother")
    assert result["win"] and result["cleanup"] and result["progress"]
    assert result["missing_alternate_floors"] == []
    assert route_evidence("\n".join(rows[1:]), "mother")["missing_alternate_floors"] == [1]
    assert route_evidence("\n".join(rows).replace("type=4", "type=0"), "mother")[
        "missing_alternate_floors"
    ] == list(range(1, 7))


def test_ending_selection_and_first_floor(tmp_path):
    script = tmp_path / "endings.lua"
    build_endings(script, ["mother", "lamb"], first_floor=True)
    assert 'local cases = { "mother", "lamb" }' in script.read_text()
    assert script.read_text().startswith("_IsaacLanTest.firstFloor = true")
    with pytest.raises(ValueError):
        build_endings(script, ["mother", "mother"])
    with pytest.raises(ValueError):
        build_endings(script, ["unknown"])


def test_boss_coverage_rejects_failed_runs_and_missing_peer():
    from check_boss_coverage import summarize

    cases = {case["key"]: {} for case in catalog()["arena"]}
    arena = {
        "passed": True,
        "restored": True,
        "peers": {role: {"passed": True, "cases": dict(cases)} for role in ("host", "client")},
    }
    ending = {
        "passed": True,
        "restored": True,
        "routes": {
            name: {
                role: {"win": True, "cleanup": True, "progress": True}
                for role in ("host", "client")
            }
            for name in ("lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent")
        },
    }
    special = {
        "passed": True,
        "restored": True,
        "cases": {
            name: {role: {"passed": True} for role in ("host", "client")}
            for name in ("greed", "greedier")
        },
    }
    assert summarize([arena], [ending], [special])["passed"]
    assert not summarize([arena], [ending], [])["passed"]
    del arena["peers"]["client"]["cases"]["boss-82"]
    assert summarize([arena], [ending], [special])["missing_arena"] == ["boss-82"]
    arena["peers"]["client"]["cases"] = dict(cases)
    ending["routes"]["mother"]["client"]["missing_alternate_floors"] = [1]
    assert not summarize([arena], [ending], [special])["passed"]
    ending["routes"]["mother"]["client"].pop("missing_alternate_floors")
    arena["restored"] = False
    assert summarize([arena], [ending], [special])["arena_passed"] == 0
    arena["restored"], arena["passed"] = True, False
    assert summarize([arena], [ending], [special])["arena_passed"] == 0


def test_interrupted_boss_coverage_requires_both_completed_assertions_and_clean_exit():
    from check_boss_coverage import summarize

    report = {
        "passed": False,
        "restored": True,
        "interrupted_cleanly": True,
        "cases": [{"key": "boss-1"}, {"key": "boss-82"}],
        "peers": {
            role: {"cases": {"boss-1": {"live": 50, "visible": 50, "views": 50}}}
            for role in ("host", "client")
        },
    }
    result = summarize([], [], [], [report])
    assert result["arena_passed"] == 1 and not result["passed"]
    assert "boss-82" in result["missing_arena"]
    report["peers"]["client"]["duplicates"] = ["boss-1"]
    assert summarize([], [], [], [report])["arena_passed"] == 0
    report["peers"]["client"]["duplicates"] = []
    report["interrupted_cleanly"] = False
    assert summarize([], [], [], [report])["arena_passed"] == 0
    assert summarize([], [], [], [report])["rejected_reports"]


def test_current_scene_checks_replica_identity_instead_of_unrelated_effect_count(tmp_path):
    import csv

    from run_client_scenes import measure

    rows = [
        {
            "phase": phase,
            "tick": tick,
            "interval_ms": 17,
            "other_entities": 120,
            "local_spray": 90,
            "replicated_spray": 0,
            "current_y": 1,
        }
        for phase, first in (("water1", 1590), ("water2", 2460))
        for tick in range(first, first + 240)
    ]
    path = tmp_path / "scenes.csv"

    def write():
        with path.open("w") as stream:
            writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)

    write()
    assert measure(path, water_only=True)["water2"]["max_replicated_spray"] == 0
    rows[-1]["replicated_spray"] = 1
    write()
    with pytest.raises(AssertionError, match="Current spray was replicated"):
        measure(path, water_only=True)
    rows[-1]["replicated_spray"] = 0
    rows[-1]["current_y"] = 0
    write()
    with pytest.raises(AssertionError, match="Missing native current"):
        measure(path, water_only=True)
