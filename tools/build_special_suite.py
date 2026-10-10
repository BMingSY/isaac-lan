#!/usr/bin/env python3
"""Combine character and side-route fixtures without restarting game processes."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ("lazarus", "poop", "knife", "hush")
DIAGNOSTICS = ("audio", "rewind", "home-debug", "home", "endings")


def build(output, cases=CASES):
    fixtures = []
    for name in cases:
        filename = {
            "lazarus": "state_lazarus_mines.lua",
            "audio": "state_guest_presentation_audio.lua",
            "home": "state_endings.lua",
            "home-debug": "state_endings.lua",
            "rewind": "state_hourglass.lua",
            "endings": "state_endings.lua",
        }.get(name, "state_side_routes.lua")
        source = (ROOT / "tests" / filename).read_text()
        if name in ("home", "home-debug"):
            source = source.replace(
                'local cases = { "lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent" }',
                'local cases = { "ascent" }',
            )
        fixtures.append(
            'function() _IsaacLanTest.route = "'
            + name
            + '"\n_IsaacLanTest.homeOnly = '
            + ("true" if name in ("home", "home-debug") else "false")
            + "\n_IsaacLanTest.debug10 = "
            + ("true" if name == "home-debug" else "false")
            + "\n_IsaacLanTest.consoleRewind = "
            + ("true" if name == "rewind" else "false")
            + "\n"
            + source
            + "\nreturn function() return "
            + ("ended" if name == "audio" else "finished")
            + " end end"
        )
    driver = (ROOT / "tests/special_suite_driver.lua").read_text()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("local fixtures = {\n" + ",\n".join(fixtures) + "\n}\n" + driver)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", choices=CASES + DIAGNOSTICS, action="append")
    args = parser.parse_args()
    build(args.output, args.case or CASES)
