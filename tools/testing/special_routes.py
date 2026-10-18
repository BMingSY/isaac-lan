"""Combine character and side-route fixtures without restarting game processes."""

from testing.lua import ROOT, factory, write_suite
import re


CASES = ("lazarus", "poop", "knife", "hush")
DIAGNOSTICS = (
    "item-generation",
    "deep-pockets",
    "party-compat",
    "death-certificate",
    "victory-lap",
    "victory-no",
    "audio",
    "rewind",
    "home-debug",
    "home",
    "endings",
    "motion",
    "action-prediction",
    "entity-fields",
    "local-hud",
    "guest-visuals",
    "floor-items",
    "floor-sources",
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
    "hornfel",
)


def build(output, cases=CASES, *, first_floor=False):
    if not cases or len(set(cases)) != len(cases) or not set(cases) <= set(CASES + DIAGNOSTICS):
        raise ValueError("Choose distinct known special routes")
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
            "action-prediction": "state_action_prediction.lua",
            "entity-fields": "state_entity_fields.lua",
            "local-hud": "state_local_hud.lua",
            "guest-visuals": "state_guest_visuals.lua",
            "floor-items": "state_floor_items.lua",
            "floor-sources": "state_floor_sources.lua",
            "mod-integrations": "state_mod_integrations.lua",
            "shared-curses": "state_shared_curses.lua",
            "shared-deals": "state_shared_deals.lua",
            "party-compat": "state_party_compat.lua",
            "death-certificate": "state_death_certificate.lua",
            "item-generation": "state_item_generation.lua",
            "deep-pockets": "state_deep_pockets.lua",
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
            "hornfel": "state_hornfel.lua",
        }.get(name, "state_side_routes.lua")
        options = {
            "route": name,
            "homeOnly": name in ("home", "home-debug", "dogma-warning"),
            "dogmaWarning": name in ("dogma-warning", "ascent-compat"),
            "crawlspace": name == "ascent-compat",
            "debug10": name == "home-debug",
            "consoleRewind": name == "rewind",
            "campaign": name == "campaign",
            "victoryLap": name == "victory-lap",
            "victoryNo": name == "victory-no",
            "firstFloor": first_floor and name == "endings",
            "greedCampaign": name in ("greed", "greedier"),
        }
        if name in ("home", "home-debug", "dogma-warning", "ascent-compat"):
            options["endingRoutes"] = ["ascent"]
        elif name in ("campaign", "victory-lap", "victory-no"):
            options["endingRoutes"] = ["lamb"]
        prelude = ""
        if name == "entity-fields":
            prelude = (
                "local createEntityFieldsProbe = (function()\n"
                + (ROOT / "tests/fixtures/entity_fields_probe.lua").read_text()
                + "\nend)()\n"
            )
        fixtures.append(factory(filename, options=options, prelude=prelude))
    write_suite(output, fixtures)


def lanbot_behavior_passed(checkpoints):
    expected = {
        "exit-pickup",
        "arrival",
        "buttons",
        "cleared-spikes",
        "timed-spikes",
        "crossing-projectiles",
        "door-transfer",
        "poop-obstacle",
        "brown-fire-obstacle",
        "red-fire-obstacle",
    }
    checks = [
        re.search(r"LANBOT_CASE (\S+) passed=(true|false)(?: |$)", line) for line in checkpoints
    ]
    checks = [check for check in checks if check]
    return (
        len(checks) == len(expected)
        and {check[1] for check in checks} == expected
        and all(check[2] == "true" for check in checks)
    )


def lanbot_greed_result(checkpoints):
    results = [
        line.split("LANBOT_GREED RESULT ", 1)[1]
        for line in checkpoints
        if "LANBOT_GREED RESULT " in line
    ]
    if len(results) != 1:
        raise ValueError("Expected exactly one authoritative LANBOT Greed result")
    values = dict(word.split("=", 1) for word in results[0].split())
    if values.get("outcome") not in {"win", "death", "stalled", "timeout", "bot_error"}:
        raise ValueError("Unknown LANBOT Greed outcome")
    won = values["outcome"] == "win"
    if values.get("cleared") != str(won).lower():
        raise ValueError("Greed outcome disagrees with the cleared flag")
    for name in ("stage", "wave", "shots0", "shots1", "hits0", "hits1"):
        values[name] = int(values[name])
    for name in ("wall_s", "simulation_s"):
        values[name] = float(values[name])
    values["cleared"] = won
    values["native_ending"] = values.get("native_ending") == "true"
    if won and (values["stage"] != 7 or not values["native_ending"]):
        raise ValueError("Greed win requires a native final-floor ending")
    return values
