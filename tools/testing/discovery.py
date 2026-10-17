"""Discover native test files without importing runners or executing fixtures."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]


def inventory():
    directory = ROOT / "tools"
    runners = set(directory.glob("run_*.py"))
    runners.discard(directory / "run_network_engine.py")  # Low-level backend.
    # Preserve the two entry points that predate the run_ naming convention.
    runners.update(directory / name for name in ("manual_gameplay.py", "validate_replica.py"))
    suites = [
        {
            "id": path.stem.removeprefix("run_").replace("_", "-"),
            "entry": path.relative_to(ROOT).as_posix(),
        }
        for path in sorted(runners)
        if path.is_file()
    ]
    if len({entry["id"] for entry in suites}) != len(suites):
        raise ValueError("Runner filenames produce duplicate suite identifiers")
    return {
        "requires_game": True,
        "suites": sorted(suites, key=lambda entry: entry["id"]),
        "fixtures": [
            {"id": path.stem.removeprefix("state_").replace("_", "-"), "script": path.name}
            for path in sorted((ROOT / "tests").glob("state_*.lua"))
            if path.is_file()
        ],
    }


def suite_command(name, arguments):
    suite = next((entry for entry in inventory()["suites"] if entry["id"] == name), None)
    if suite is None:
        raise ValueError("Unknown native test suite: " + name)
    return [sys.executable, str(ROOT / suite["entry"]), *arguments]
