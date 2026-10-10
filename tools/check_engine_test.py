#!/usr/bin/env python3
"""Check evidence from the isolated in-game room experiment, not network gameplay."""

import argparse
import hashlib
import json
from pathlib import Path
import re
from game_logs import probe_text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lab", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.lab.resolve()
    if not (root / ".isaac-lan-lab").is_file():
        raise SystemExit("Only a marked isolated lab is supported")
    probe = probe_text(root)
    probe = "bootstrap=" + probe.rsplit("bootstrap=", 1)[-1]
    game = (root / "profile/Documents/My Games/Binding of Isaac Repentance+/log.txt").read_text(
        errors="replace"
    )
    result = re.search(
        r"LAN_ROOM_ISOLATION pass=(\w+) updates=(\d+),(\d+) collisions=(\d+),(\d+) "
        r"hearts=(\d+),(\d+) initial=(\d+),(\d+)",
        game,
    )
    ticks = re.search(
        r"room_poll=300 foreground_native_updates=(\d+) background_native_updates=(\d+) "
        r"foreground_half_updates=(\d+) background_half_updates=(\d+)",
        probe,
    )
    checks = {
        "single_experiment": game.count("LAN_NATIVE_TEST_STARTED") == 1
        and probe.count("room_create=BEGIN") == 1,
        "version_and_isolation": "bootstrap=PASS version=1.9.7.17.J460 isolation=profile_redirect"
        in probe,
        "native_layout": probe.count("audit=PASS") == 10 and "audit=FAIL" not in probe,
        "native_calls": bool(ticks)
        and ticks[1] == ticks[2] == "300"
        and ticks[3] == ticks[4]
        and int(ticks[3]) > 0,
        "player_callbacks_and_collisions": bool(result)
        and result[1] == "true"
        and int(result[2]) == int(result[3]) >= 300
        and int(result[4]) == 0
        and int(result[5]) > 0
        and result[6] == result[8]
        and int(result[7]) < int(result[9]),
        "room_lifetime": "room_cleanup=RETURNED" in probe and "LAN_ROOM_RESTORED" in game,
        "finished": "LAN_ROOM_EXPERIMENT_FINISHED" in game,
        "no_exceptions": "native_exception=" not in probe
        and 'Error in "' not in game
        and "LAN_ROOM_EXPERIMENT_FAILED" not in game,
    }
    evidence = {
        "kind": "isolated-native-two-room-experiment",
        "not_tested": [
            "LAN networking",
            "independent transitions",
            "floor changes",
            "mod compatibility",
            "complete co-op gameplay",
        ],
        "game_sha256": hashlib.sha256((root / "game/isaac-ng.exe").read_bytes()).hexdigest(),
        "probe_sha256": hashlib.sha256(
            (root / "game/isaac_lan_probe.dll").read_bytes()
        ).hexdigest(),
        "harness_sha256": hashlib.sha256(
            (root / "game/mods/lan_native_internal_probe/main.lua").read_bytes()
        ).hexdigest(),
        "checks": checks,
        "passed": all(checks.values()),
        "native_counters": ticks[0] if ticks else None,
        "isolation_result": result[0] if result else None,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2) + "\n")
    args.output.with_suffix(".native.log").write_text(probe)
    args.output.with_suffix(".game.log").write_text(game)
    print(json.dumps(evidence, indent=2))
    raise SystemExit(0 if evidence["passed"] else 1)


if __name__ == "__main__":
    main()
