"""Build the native ending-route fixture, optionally selecting diagnostic routes."""

from testing.lua import factory
import re


CASES = ("lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent")


def build(output, routes=None, *, first_floor=False):
    if routes is not None and (
        not routes or len(set(routes)) != len(routes) or any(route not in CASES for route in routes)
    ):
        raise ValueError("Choose distinct known ending routes")
    options = {"firstFloor": first_floor, "endingRoutes": list(routes or CASES)}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("(" + factory("state_endings.lua", options=options) + ")()\n")


def route_evidence(text, name):
    lines = [line for line in text.splitlines() if "ENDINGS " + name + " " in line]
    floors = sorted(
        {
            (int(stage), int(kind))
            for line in lines
            for stage, kind in re.findall(r"ROUTE_FLOOR stage=(\d+) type=(\d+)", line)
        }
    )
    missing = [
        stage
        for stage in range(1, 7)
        if name == "mother" and not any((stage, kind) in floors for kind in (4, 5))
    ]
    return {
        "win": any(
            "NATIVE_WIN callback=MC_POST_GAME_END game_over=false" in line for line in lines
        ),
        "cleanup": any("PASS native ending and session cleanup" in line for line in lines),
        "progress": any("LOCAL_PROGRESS_RESTORED" in line for line in lines),
        "floors": floors,
        "missing_alternate_floors": missing,
        "checkpoints": lines,
    }
