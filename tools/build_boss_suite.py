#!/usr/bin/env python3
"""Build a deterministic shard of native Boss-room acceptance cases."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shards", type=int, default=1)
    parser.add_argument("--case", action="append")
    args = parser.parse_args()
    build(args.output, args.shard, args.shards, args.case)
