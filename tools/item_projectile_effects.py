"""Collision-based defense trials with a native damaging control projectile."""

ENTITY_FAMILIAR = 3
ISAACS_HEART_FAMILIAR = 62
PROJECTILE_EFFECTS = {}
for name, kind, familiar, extra in (
    ("INFAMY", "player", None, {}),
    ("TRINITY_SHIELD", "player", None, {"shoot": True}),
    ("LOST_CONTACT", "player", None, {"shoot": True, "tear_flags": ["TEAR_SHIELDED"]}),
    ("METAL_PLATE", "player", None, {"reflected": True}),
    ("JELLY_BELLY", "player", None, {"reflected": True}),
    ("PSY_FLY", "player", "PSY_FLY", {}),
    ("BOT_FLY", "player", "BOT_FLY", {}),
    ("LIL_DUMPY", "player", "LIL_DUMPY", {"rearm": True}),
    ("DRY_BABY", "familiar", "DRY_BABY", {"enemies": 1, "enemy_hurt": True}),
    (
        "FARTING_BABY",
        "familiar",
        "FARTING_BABY",
        {"enemies": 1, "enemy_hurt": True, "target_familiar": "FARTING_BABY"},
    ),
    ("SLIPPED_RIB", "familiar", "SLIPPED_RIB", {"reflected": True}),
    ("MILK", "familiar", "MILK", {"milk_breaks": True}),
    ("TINYTOMA", "familiar", "TINYTOMA", {"splits": True}),
    ("SWARM", "familiar", "SWARM_FLY_ORBITAL", {"blue_fly": True}),
    ("PUNCHING_BAG", "familiar", "PUNCHING_BAG", {}),
    ("ISAACS_HEART", "player", "ISAACS_HEART", {"heart_hit": True, "heart_trials": 3}),
):
    PROJECTILE_EFFECTS["COLLECTIBLE_" + name] = {
        "projectile_trial": {"kind": kind, "familiar": familiar, **extra},
        "shoot": extra.get("shoot", False),
        "shoot_until": 1620,
        "observe_until": 1740 if extra.get("heart_hit") else 1620,
        "end_tick": 1770 if extra.get("heart_hit") else 1650,
        **{
            key: value
            for key, value in extra.items()
            if key in ("tear_flags", "enemies", "enemy_hurt", "target_familiar")
        },
    }


def projectile_checks(rules, observations, probes, check):
    trial = rules.get("projectile_trial")
    if not trial:
        return
    events = observations.get("host", [])
    results = [e for e in events if e["event"] == "defense_projectile_result"]
    control = [e for e in results if e["control"]]
    defense = [e for e in results if not e["control"]]
    check(
        "ordinary_projectile_control_causes_damage",
        [len(control) == 1 and control[0]["after"] < control[0]["before"]],
    )
    minimum = (
        10
        if trial.get("milk_breaks")
        else 3
        if trial.get("splits")
        else 8
        if trial.get("blue_fly")
        else 20
    )
    check("repeated_native_projectile_collisions", [len(defense) >= minimum])
    if trial["kind"] == "player":
        check(
            "item_prevents_projectile_damage",
            [any(e["after"] == e["before"] and (e["removed"] or e["reflected"]) for e in defense)],
        )
    else:
        check(
            "familiar_intercepts_projectiles",
            [
                any(
                    e["collision"] and e.get("collider") == 3 and (e["removed"] or e["reflected"])
                    for e in defense
                )
            ],
        )
    if trial.get("reflected"):
        check("projectile_reflected_by_native_effect", [any(e["reflected"] for e in defense)])
    values = [e for e in events if e["event"] == "defense_state"]
    if trial.get("milk_breaks"):
        check(
            "milk_breaks_and_grants_tears",
            [
                bool(values)
                and min(e["delay"] for e in values if e["tick"] > 600) < values[0]["delay"]
            ],
        )
    if trial.get("splits"):
        check(
            "tinytoma_splits_and_releases_spiders",
            [any(e["small_tomas"] > 0 for e in values), any(e["spiders"] > 0 for e in values)],
        )
    if trial.get("blue_fly"):
        check("swarm_converts_blocker_to_attack_fly", [any(e["blue_flies"] > 0 for e in values)])
    if trial.get("heart_hit"):
        hits = [e for e in events if e["event"] == "heart_familiar_damage"]
        contacts = [
            e
            for e in hits
            if e.get("collision")
            and e.get("collider_type") == ENTITY_FAMILIAR
            and e.get("collider_variant") == ISAACS_HEART_FAMILIAR
        ]
        check("heart_projectiles_reach_familiar", [len(contacts) >= 2])
        check(
            "heart_familiar_still_takes_owner_damage",
            [bool(contacts) and all(e["after"] < e["before"] for e in contacts)],
        )
