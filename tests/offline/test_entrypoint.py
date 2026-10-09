"""The offline entry point has no path to a game launcher."""

from pathlib import Path

from test import ROOT, engine_catalog, plan


def test_catalog_reads_engine_inventory_without_import_or_execution(monkeypatch):
    def forbidden(*args, **kwargs):
        raise AssertionError("Listing engine metadata attempted to execute a process")

    monkeypatch.setattr("subprocess.run", forbidden)
    monkeypatch.setattr("subprocess.Popen", forbidden)
    catalog = engine_catalog()
    registered = {entry["script"] for entry in catalog["registered"]}
    legacy = set(catalog["unregistered_scripts"])
    existing = {path.name for path in (ROOT / "tests").glob("state_*.lua")}
    assert registered.isdisjoint(legacy)
    assert registered | legacy == existing
    assert catalog["requires_game"] is True


def test_every_profile_configures_portable_tests_and_never_plans_a_game_launch():
    for profile in ("fast", "full"):
        commands = dict(plan(Path("build-offline"), Path("test-runs/offline"), profile, "lua5.3"))
        assert "-DISAAC_LAN_BUILD_ENGINE=OFF" in commands["configure"]
        assert "-DISAAC_LAN_LUA=lua5.3" in commands["configure"]
        assert commands["core"][-2:] == ["-L", "offline"]
        assert commands["scenarios"][1:3] == ["-m", "pytest"]
        for command in commands.values():
            assert not any(
                "isaac-ng" in arg
                or "run_network_engine" in arg
                or "manual_gameplay" in arg
                or "validate_replica" in arg
                for arg in command
            )
