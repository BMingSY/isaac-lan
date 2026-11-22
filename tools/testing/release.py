"""Reusable native suite construction."""

import json
from game_profiles import DEFAULT_BACKEND
from testing.lua import factory, write_suite
from testing.pause import ITEMS_PAGE


HOURGLASS = (
    "cross-floor",
    "greed-start",
    "greed-neighbor",
    "greedier-start",
    "greedier-neighbor",
)
CASES = ("smoke", *HOURGLASS, "pause", "solo")
COMPLETION = "LAN_NETWORK PASS all selected character and side routes"


def build_suite(output, coordination, cases=CASES, *, backend=DEFAULT_BACKEND):
    """Keep each fixture's callbacks and frame/gate wrappers inside its factory."""
    if not cases or len(set(cases)) != len(cases) or not set(cases) <= set(CASES):
        raise ValueError("Choose distinct known release cases")
    coordination = str(coordination).replace("\\", "/").rstrip("/")
    first_visit = {"j835": "rewind", "j511": "error-room"}[backend]
    factories = []
    for name in cases:
        prefix = ""
        options = None
        filename = "state_release_" + name + ".lua"
        if name in HOURGLASS:
            filename = "state_release_hourglass.lua"
            options = {"releaseHourglass": name, "greedStartDestination": first_visit}
        elif name == "pause":
            filename = "state_pause_menu.lua"
            options = {"pauseItemsPage": ITEMS_PAGE[backend]}
            prefix = (
                "local pauseCoordination = "
                + json.dumps(coordination + "/pause")
                + "\nlocal pausePulses = 8\n"
            )
        elif name == "solo":
            prefix = "_IsaacLanTest.releaseCoordination = " + json.dumps(coordination) + "\n"
        factories.append(factory(filename, options=options, prelude=prefix))
    write_suite(output, factories)
