#!/usr/bin/env python3
"""Audit frozen state-sync scenarios and per-process engine evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import re


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(directory):
    result = json.loads((directory / "result.json").read_text())
    assert result["pass"] and not result.get("error") and not result.get("close_errors"), directory
    assert digest(directory / "tested-probe.dll") == result["dll_sha256"]
    assert digest(directory / "test-harness.lua") == result["script_sha256"]
    assert 2 <= len(result["runs"]) <= 4
    audit = {
        "directory": directory.name,
        "dll_sha256": result["dll_sha256"],
        "script_sha256": result["script_sha256"],
        "peers": [],
        "one_way_latency_ms": result.get("one_way_latency_ms", 0),
    }
    for peer in result["runs"]:
        role = peer["role"]
        game = (directory / role / "log.txt").read_text(errors="replace")
        native = (
            (directory / role / "probe.log")
            .read_text(errors="replace")
            .rsplit("bootstrap=PASS", 1)[-1]
        )
        assert "LAN_NETWORK PASS " in game and "ISAAC_LAN READY players=" in game, (directory, role)
        for token in ("LAN_NETWORK FAILED", "Error in", "Caught exception"):
            assert token not in game, (directory, role, token)
        for token in ("network_failure=", "frontend_error=", "native_exception", "rooms_fatal="):
            assert token not in native, (directory, role, token)
        expected = "state_authority=HOST" if role == "host" else "state_authority=REPLICA"
        assert expected in native, (directory, role, expected)
        receipts = re.findall(r"CLIENT corrected=(\d+) hostTick=(\d+)", game)
        views = re.findall(r"VIEW tick=(\d+) room=(-?\d+) pos=([^ ]+) screen=([^ ]+)", game)
        checkpoints = re.findall(r"floor_checkpoint=RESTORED tick=(\d+)", native)
        audit["peers"].append(
            {
                "role": role,
                "completion": re.findall(r"LAN_NETWORK PASS (.*)", game),
                "corrections": receipts[-1:] or [],
                "camera_samples": len(views),
                "floor_restores": checkpoints,
            }
        )
    host = (
        (directory / "host/probe.log").read_text(errors="replace").rsplit("bootstrap=PASS", 1)[-1]
    )
    audit["state_sizes"] = [
        {"slot": int(slot), "tick": int(tick), "raw": int(raw), "wire": int(wire)}
        for slot, tick, raw, wire in re.findall(
            r"state_transfer slot=(\d+) tick=(\d+) raw=(\d+) wire=(\d+)", host
        )
    ]
    assert audit["state_sizes"], (directory, "No host state publication evidence")
    return audit


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    audits = [check(directory) for directory in args.directories]
    args.output.write_text(
        json.dumps(
            {"format": 1, "model": "host-authoritative state sync", "runs": audits}, indent=2
        )
        + "\n"
    )
    print(f"PASS: {len(audits)} frozen scenarios; all peer logs and payload hashes verified")
