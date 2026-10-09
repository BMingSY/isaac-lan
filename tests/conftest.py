"""Offline profiles and Lua fixtures. No fixture imports a game launcher."""

from pathlib import Path
import re
import sys

from hypothesis import HealthCheck, settings
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from offline_lua import LuaWorker


def pytest_addoption(parser):
    parser.addoption("--offline-profile", choices=("fast", "full"), default="fast")
    parser.addoption("--offline-report-dir", default=str(ROOT / "test-runs/pytest"))


def pytest_configure(config):
    # A persistent worker is shared across generated examples. Stateful cases
    # explicitly reset their world; codec cases have no mutable state.
    common = {"deadline": None, "suppress_health_check": [HealthCheck.function_scoped_fixture]}
    settings.register_profile("fast", max_examples=25, stateful_step_count=20, **common)
    settings.register_profile("full", max_examples=200, stateful_step_count=60, **common)
    settings.load_profile(config.getoption("--offline-profile"))


@pytest.fixture
def lua():
    worker = LuaWorker()
    try:
        yield worker
    finally:
        worker.close()


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    if report.failed and "lua" in item.funcargs:
        directory = Path(item.config.getoption("--offline-report-dir"))
        directory.mkdir(parents=True, exist_ok=True)
        name = re.sub(r"[^a-zA-Z0-9_.-]", "_", item.nodeid)
        path = directory / (name + ".json")
        item.funcargs["lua"].save(path)
        report.sections.append(("Offline Lua requests/responses", str(path)))
