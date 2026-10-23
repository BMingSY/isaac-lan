"""Build a deterministic shard of native Boss-room acceptance cases."""

import json
from pathlib import Path
from collections import Counter
import re


ROOT = Path(__file__).resolve().parents[2]
MIN_SCENARIO_SECONDS = 3600
SUITE_OVERHEAD_SECONDS = 120
SECONDS_PER_CASE = 60


def scenario_timeout(case_count):
    # The overall deadline includes floor loads and transitions for every case.
    # Per-case progress deadlines remain enforced by the native fixture.
    return max(MIN_SCENARIO_SECONDS, SUITE_OVERHEAD_SECONDS + SECONDS_PER_CASE * case_count)


def catalog():
    return json.loads((ROOT / "tests/fixtures/boss_catalog.json").read_text())


def select_cases(shard=0, shards=1, keys=None):
    if not 0 <= shard < shards:
        raise ValueError("Shard must be in 0..shards-1")
    cases = catalog()["arena"]
    if keys is not None:
        known = {case["key"] for case in cases}
        if not keys or len(set(keys)) != len(keys) or not set(keys) <= known:
            raise ValueError("Choose distinct known Boss cases")
        cases = [case for case in cases if case["key"] in keys]
    return cases[shard::shards]


def lua(value):
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (str, int)):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return "{" + ",".join(key + "=" + lua(item) for key, item in value.items()) + "}"


def build(output, shard=0, shards=1, keys=None):
    cases = select_cases(shard, shards, keys)
    if not cases:
        raise ValueError("Boss shard is empty")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "local bossCases = " + lua(cases) + "\n" + (ROOT / "tests/state_all_bosses.lua").read_text()
    )
    return cases


COMPLETION = "LAN_NETWORK PASS all selected Boss encounters"


def evidence(text, cases):
    matches = re.findall(r"ALL_BOSSES PASS key=([\w-]+) live=(\d+) visible=(\d+) views=(\d+)", text)
    found = {
        key: {"live": int(live), "visible": int(visible), "views": int(views)}
        for key, live, visible, views in matches
    }
    expected = {case["key"] for case in cases}
    return {
        "passed": COMPLETION in text
        and set(found) == expected
        and len(matches) == len(expected)
        and all(value["live"] >= 30 and value["visible"] >= 10 for value in found.values())
        and "LAN_NETWORK FAILED" not in text,
        "missing": sorted(expected - found.keys()),
        "duplicates": sorted(
            key for key, count in Counter(match[0] for match in matches).items() if count > 1
        ),
        "cases": found,
        "forms": re.findall(r"ALL_BOSSES FORM key=([\w-]+) entity=([\d:]+)", text),
    }
