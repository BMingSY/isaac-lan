"""Exercise the actual mixed-load fixture without launching the game."""

from pathlib import Path
import shutil
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]
CASES = (
    "startup-host",
    "startup-client",
    "unconfirmed",
    "not-ready",
    "success",
    "missing-replica",
    "replacement",
    "pool-budget",
    "cleanup-reuse",
    "incomplete",
    "room-escape",
)


@pytest.mark.parametrize("case", CASES)
def test_actual_entity_capacity_fixture(case):
    lua = shutil.which("lua5.3") or shutil.which("lua")
    assert lua, "Lua 5.3 is required"
    result = subprocess.run(
        [
            lua,
            str(ROOT / "tests/entity_capacity_fixture.lua"),
            str(ROOT / "tests/state_entity_capacity.lua"),
            str(ROOT),
            case,
        ],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert f"PASS entity capacity fixture {case}" in result.stdout
