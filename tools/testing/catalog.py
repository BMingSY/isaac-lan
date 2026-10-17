"""Complete, read-only native test inventory. Importing this module cannot launch games."""

import json
from pathlib import Path


DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parents[1]
REPLICA_CASES = json.loads((DIRECTORY / "replica_cases.json").read_text())


def inventory():
    catalog = json.loads((DIRECTORY / "catalog.json").read_text())
    suites = catalog["suites"]
    fixtures = catalog["fixtures"]
    for values in (suites, fixtures):
        names = [entry["id"] for entry in values]
        if len(names) != len(set(names)):
            raise ValueError("Duplicate test catalog identifiers")
    known = {entry["id"] for entry in suites}
    for entry in fixtures:
        if not set(entry["suites"]) <= known:
            raise ValueError("Unknown fixture suite: " + entry["id"])
    return {"requires_game": True, **catalog}


def suite_command(name, arguments):
    import sys

    suite = next((entry for entry in inventory()["suites"] if entry["id"] == name), None)
    if suite is None:
        raise ValueError("Unknown native test suite: " + name)
    return [sys.executable, str(ROOT / suite["entry"]), *arguments]
