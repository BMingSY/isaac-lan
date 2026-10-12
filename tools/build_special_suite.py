#!/usr/bin/env python3
"""Combine character and side-route fixtures without restarting game processes."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ("lazarus", "poop", "knife", "hush")
DIAGNOSTICS = (
    "item-generation",
    "party-compat",
    "victory-lap",
    "victory-no",
    "audio",
    "rewind",
    "home-debug",
    "home",
    "endings",
    "motion",
    "floor-items",
    "mod-integrations",
    "shared-curses",
    "shared-deals",
    "dogma-warning",
    "ascent-compat",
    "greed",
    "greedier",
    "campaign",
    "lanbot",
    "lanbot-campaign",
    "lanbot-spiders",
    "lanbot-greed",
    "room-entry",
)


def build(output, cases=CASES, *, first_floor=False):
    if first_floor and "endings" not in cases:
        raise ValueError("First-floor coverage requires the six ending routes")
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
            "shared-deals": "state_shared_deals.lua",
            "party-compat": "state_party_compat.lua",
            "item-generation": "state_item_generation.lua",
            "victory-lap": "state_endings.lua",
            "victory-no": "state_endings.lua",
            "greed": "state_greed.lua",
            "greedier": "state_greed.lua",
            "dogma-warning": "state_endings.lua",
            "ascent-compat": "state_endings.lua",
            "campaign": "state_endings.lua",
            "lanbot": "state_lanbot.lua",
            "lanbot-campaign": "state_lanbot_campaign.lua",
            "lanbot-spiders": "state_lanbot_spiders.lua",
            "lanbot-greed": "state_lanbot_greed.lua",
            "room-entry": "state_room_entry.lua",
        }.get(name, "state_side_routes.lua")
        source = (ROOT / "tests" / filename).read_text()
        if name in ("home", "home-debug", "dogma-warning", "ascent-compat"):
            source = source.replace(
                'local cases = { "lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent" }',
                'local cases = { "ascent" }',
            )
        elif name in ("campaign", "victory-lap", "victory-no"):
            source = source.replace(
                'local cases = { "lamb", "blue-baby", "delirium", "mega-satan", "mother", "ascent" }',
                'local cases = { "lamb" }',
            )
        cleanup = ""
        if name == "motion":
            cleanup = "if motionFile then motionFile:close(); motionFile = nil end\n"
        elif name == "mod-integrations":
            cleanup = "native.api_send, native.api_receive = send, receive\nlan:Unregister()\n"
        elif name in ("greed", "greedier", "victory-lap", "victory-no"):
            cleanup = "Isaac.RemoveCallback(owner, ModCallbacks.MC_POST_GAME_END, winCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, exitCallback)\n"
            if name in ("victory-lap", "victory-no"):
                cleanup += "Isaac.RemoveCallback(owner, ModCallbacks.MC_PRE_PICKUP_COLLISION, chestCallback)\n"
        elif name == "lanbot":
            cleanup = 'command("off")\nIsaac.RemoveCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, damageCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, tearCallback)\n'
        elif name == "lanbot-campaign":
            cleanup = 'command("off")\nnative.input_bot = baseInput\nIsaac.RemoveCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, tearCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_PRE_PICKUP_COLLISION, chestCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_POST_GAME_END, winCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_PRE_GAME_EXIT, exitCallback)\n'
        elif name == "lanbot-spiders":
            cleanup = 'command("off")\nnative.input_bot = baseInput\nIsaac.RemoveCallback(owner, ModCallbacks.MC_PRE_NPC_UPDATE, freezeCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, damageCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, tearCallback)\n'
        elif name == "lanbot-greed":
            cleanup = 'command("off")\nnative.input_bot = baseInput\nIsaac.RemoveCallback(owner, ModCallbacks.MC_POST_GAME_END, winCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, damageCallback)\nIsaac.RemoveCallback(owner, ModCallbacks.MC_POST_FIRE_TEAR, tearCallback)\n'
        elif name == "shared-deals":
            cleanup = (
                "Isaac.RemoveCallback(owner, ModCallbacks.MC_PRE_NPC_UPDATE, freezeCallback)\n"
            )
        elif name == "room-entry":
            cleanup = "native.input_bot = baseInput\nnative.input_bot(0, 0)\n"
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
            + "\n_IsaacLanTest.victoryLap = "
            + ("true" if name == "victory-lap" else "false")
            + "\n_IsaacLanTest.victoryNo = "
            + ("true" if name == "victory-no" else "false")
            + "\n_IsaacLanTest.firstFloor = "
            + ("true" if first_floor and name == "endings" else "false")
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
    parser.add_argument("--first-floor", action="store_true")
    args = parser.parse_args()
    build(args.output, args.case or CASES, first_floor=args.first_floor)
