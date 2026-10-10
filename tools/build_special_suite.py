#!/usr/bin/env python3
"""Combine character and side-route fixtures without restarting game processes."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ("lazarus", "poop", "knife", "hush")
DIAGNOSTICS = (
    "audio",
    "rewind",
    "home-debug",
    "home",
    "endings",
    "motion",
    "floor-items",
    "mod-integrations",
    "shared-curses",
    "dogma-warning",
    "ascent-compat",
    "greed",
    "greedier",
    "campaign",
    "lanbot",
    "lanbot-campaign",
)


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
            "motion": "state_motion.lua",
            "floor-items": "state_floor_items.lua",
            "mod-integrations": "state_mod_integrations.lua",
            "shared-curses": "state_shared_curses.lua",
            "greed": "state_greed.lua",
            "greedier": "state_greed.lua",
            "dogma-warning": "state_endings.lua",
            "ascent-compat": "state_endings.lua",
            "campaign": "state_endings.lua",
            "lanbot": "state_lanbot.lua",
            "lanbot-campaign": "state_lanbot_campaign.lua",
        }.get(name, "state_side_routes.lua")
        source = (ROOT / "tests" / filename).read_text()
        if name in ("home", "home-debug", "dogma-warning", "ascent-compat"):
            source = source.replace(
                'local cases = { "lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent" }',
                'local cases = { "ascent" }',
            )
        elif name == "campaign":
            source = source.replace(
                'local cases = { "lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent" }',
                'local cases = { "lamb" }',
            )
        cleanup = ""
        if name == "motion":
            cleanup = "if motionFile then motionFile:close(); motionFile = nil end\n"
        elif name == "mod-integrations":
            cleanup = "native.api_send, native.api_receive = send, receive\nlan:Unregister()\n"
        elif name in ("greed", "greedier"):
            cleanup = "Isaac.RemoveCallback(owner, ModCallbacks.MC_POST_GAME_END, winCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, exitCallback)\n"
        elif name == "lanbot":
            cleanup = 'command("off")\nIsaac.RemoveCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, damageCallback)\n'
        elif name == "lanbot-campaign":
            cleanup = 'command("off")\nnative.input_bot = baseInput\nIsaac.RemoveCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, tearCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_PRE_PICKUP_COLLISION, chestCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_POST_GAME_END, winCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, exitCallback)\n'
        complete = {"audio": "ended", "lanbot": "done"}.get(name, "finished")
        fixtures.append(
            'function() _IsaacLanTest.route = "'
            + name
            + '"\n_IsaacLanTest.homeOnly = '
            + ("true" if name in ("home", "home-debug", "dogma-warning") else "false")
            + "\n_IsaacLanTest.dogmaWarning = "
            + ("true" if name in ("dogma-warning", "ascent-compat") else "false")
            + "\n_IsaacLanTest.crawlspace = "
            + ("true" if name == "ascent-compat" else "false")
            + "\n_IsaacLanTest.debug10 = "
            + ("true" if name == "home-debug" else "false")
            + "\n_IsaacLanTest.consoleRewind = "
            + ("true" if name == "rewind" else "false")
            + "\n_IsaacLanTest.campaign = "
            + ("true" if name == "campaign" else "false")
            + "\n_IsaacLanTest.greedCampaign = "
            + ("true" if name in ("greed", "greedier") else "false")
            + "\n"
            + source
            + "\nlocal cleanedUp = false\nreturn function()\nif "
            + complete
            + " and not cleanedUp then\ncleanedUp = true\n"
            + cleanup
            + "native.test_gamepad(0)\nend\nreturn "
            + complete
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
