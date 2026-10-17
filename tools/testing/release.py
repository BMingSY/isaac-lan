"""Reusable native suite construction."""

import json
from testing.lua import factory, write_suite


HOURGLASS = (
    "cross-floor",
    "greed-start",
    "greed-neighbor",
    "greedier-start",
    "greedier-neighbor",
)
CASES = ("smoke", *HOURGLASS, "pause", "solo")
COMPLETION = "LAN_NETWORK PASS all selected character and side routes"


def build_suite(output, coordination, cases=CASES):
    """Keep each fixture's callbacks and frame/gate wrappers inside its factory."""
    if not cases or len(set(cases)) != len(cases) or not set(cases) <= set(CASES):
        raise ValueError("Choose distinct known release cases")
    coordination = str(coordination).replace("\\", "/").rstrip("/")
    factories = []
    for name in cases:
        prefix = ""
        filename = "state_release_" + name + ".lua"
        if name in HOURGLASS:
            filename = "state_release_hourglass.lua"
            prefix = "_IsaacLanTest.releaseHourglass = " + json.dumps(name) + "\n"
        elif name == "pause":
            filename = "state_pause_menu.lua"
            prefix = (
                "local pauseCoordination = "
                + json.dumps(coordination + "/pause")
                + "\nlocal pausePulses = 8\n"
            )
        elif name == "solo":
            prefix = "_IsaacLanTest.releaseCoordination = " + json.dumps(coordination) + "\n"
        factories.append(factory(filename, prelude=prefix))
    write_suite(output, factories)
