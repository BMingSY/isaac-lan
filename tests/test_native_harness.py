"""Exercise harness behavior without a game, including interruption and cleanup."""

import json
import shutil
import subprocess
import sys
from xml.etree import ElementTree as ET

import pytest

import lab_profile
from testing.discovery import ROOT, inventory, suite_command
from testing.engine import BackendCleanupError, engine_process
from testing.results import finish_run
from testing import lua as lua_support
from testing.special_routes import build as build_special
from testing.endings import build as build_endings
from testing import gameplay as build_gameplay_suite
from testing import discovery
from run_mouse_input import ready_peers
from run_network_engine import read_log
from game_logs import log_path


@pytest.mark.parametrize(
    "event", ["[INFO] - Updating mod 'Isaac LAN'", "[INFO] - Lua is resetting!"]
)
@pytest.mark.parametrize("started", [False, True])
def test_engine_rejects_runtime_reload_even_with_completion(tmp_path, event, started):
    lab = tmp_path / "owned-host"
    log = log_path(lab)
    log.parent.mkdir(parents=True)
    text = "[INFO] - Running Lua Script: resources/scripts/main.lua\n"
    if started:
        text += "[INFO] - Lua Debug: LAN_NETWORK SPECIAL_CASE_PASS index=1\n"
    log.write_text(text + event + "\n[INFO] - Lua Debug: LAN_NETWORK PASS all selected routes\n")
    with pytest.raises(RuntimeError, match="owned-host: runtime changed during the frozen test"):
        read_log(lab)
    assert event in log.read_text()  # Keep the original evidence for archiving.


def test_engine_accepts_normal_lua_startup_and_literal_scenario_messages(tmp_path):
    assert read_log(tmp_path) == ""
    log = log_path(tmp_path)
    log.parent.mkdir(parents=True)
    text = (
        "[INFO] - Running Lua Script: resources/scripts/enums.lua\n"
        "[INFO] - Running Lua Script: resources/scripts/main.lua\n"
        "[INFO] - Lua Debug: LAN_NETWORK MESSAGE Lua is resetting!\n"
        "[INFO] - Lua Debug: LAN_NETWORK MESSAGE Updating mod 'example'\n"
    )
    log.write_text(text)
    assert read_log(tmp_path) == text


def test_mouse_restart_waits_for_new_peers_and_recreated_logs(tmp_path):
    labs = [tmp_path / role for role in ("host", "client")]
    for lab in labs:
        log = log_path(lab)
        log.parent.mkdir(parents=True)
        log.write_text("LAN_NETWORK MOUSE READY\n")
    launch = tmp_path / "round-02.log"
    launch.write_text("")
    assert ready_peers(launch, labs) is None
    launch.write_text("Started isolated host: 100\n")
    assert ready_peers(launch, labs) is None
    log_path(labs[1]).unlink()
    launch.write_text("Started isolated host: 100\nStarted isolated client: 200\n")
    assert ready_peers(launch, labs) is None
    log_path(labs[1]).write_text("LAN_NETWORK MENU_READY\n")
    assert ready_peers(launch, labs) is None
    log_path(labs[1]).write_text("LAN_NETWORK MOUSE READY\n")
    assert ready_peers(launch, labs) == {"host": "100", "client": "200"}


def run_lua(source, tmp_path):
    script = tmp_path / "check.lua"
    script.write_text(lua_support.bundle_input(source))
    return subprocess.run(
        [shutil.which("lua5.3"), str(script)],
        text=True,
        capture_output=True,
        check=True,
    ).stdout


@pytest.mark.parametrize("lost", [False, True])
def test_tear_trajectory_excludes_prior_scenarios_but_detects_new_missing_shots(tmp_path, lost):
    run_lua(
        """
local status = { phase = 3, prepared = true, verified = 79 }
_IsaacLanTest = { host = false, port = "1234" }
_IsaacLanFrame = function() return status end
_IsaacLan = {
    net_gate = function() end,
    diagnostics_counter = function() end,
    test_gamepad = function() end,
}
CollectibleType = { COLLECTIBLE_NUMBER_ONE = 1, COLLECTIBLE_MOMS_HEELS = 30 }
Isaac = { DebugString = function() end }
package.loaded.json = { encode = function(value) return value.name or "" end }
dofile("""
        + lua_support.literal(str(ROOT / "tests/state_tear_trajectory.lua"))
        + """)
local function counters(previews, confirmed)
    for name, value in pairs({
        previews = previews, confirmed = confirmed, timed_out = 4,
        grid_stops = 5, landed = 0,
    }) do
        _IsaacLan.diagnostics_counter("attack." .. name, value)
    end
end
-- A preceding scenario left cumulative counters, including valid grid stops.
counters(151, 142)
_IsaacLanFrame()
counters(163, 154 - """
        + str(int(lost))
        + """)
status.verified = 240
local ok, message = pcall(_IsaacLanFrame)
assert(ok == """
        + lua_support.literal(not lost)
        + """, tostring(message))
if not ok then assert(message:find("A shot failed to hand over: still", 1, true)) end
""",
        tmp_path,
    )


def test_bundled_input_support_is_frozen_and_needs_no_runtime_files(tmp_path, monkeypatch):
    support = tmp_path / "tests/support/input.lua"
    support.parent.mkdir(parents=True)
    shutil.copyfile(ROOT / "tests/support/input.lua", support)
    monkeypatch.setattr(lua_support, "ROOT", tmp_path)
    script = tmp_path / "frozen.lua"
    script.write_text(
        "io, dofile, loadfile, require, debug = nil, nil, nil, nil, nil\n"
        + lua_support.bundle_input("""
local input = assert(_IsaacLanTestInput)
local packet = input.neutral .. input.buttons(1 << 9, 1 << 9)
local frame = input.decode(packet, 1)
assert(frame.values[9] == input.maxValue and frame.triggered == 1 << 9)
assert(not frame.pointer.active and input.decode(packet).values[9] == 0)
print("PASS frozen fixture support")
""")
    )
    support.unlink()
    result = subprocess.run(
        [shutil.which("lua5.3"), str(script)], capture_output=True, text=True, check=True
    )
    assert "PASS frozen fixture support" in result.stdout


@pytest.mark.parametrize("host", [True, False])
def test_motion_fixture_rejects_room_drift_and_restores_its_doors(tmp_path, host):
    run_lua(
        """
local function noop() end
local status = { phase = 3, prepared = true, verified = 0 }
local locations = { ["0"] = { index = 84, dimension = 0 }, ["1"] = { index = 84, dimension = 0 } }
local door = { opened = true, locked = false }
function door:IsOpen() return self.opened end
function door:IsLocked() return self.locked end
function door:Close(force) assert(force); self.opened = false end
function door:Open() self.opened = true end
function door:SetLocked(value) self.locked = value end
local room = {
    GetGridSize = function() return 0 end,
    GetDoor = function(_, slot) return slot == 2 and door or nil end,
}
local players = {}
for i = 0, 1 do
    players[i] = { SetMinDamageCooldown = noop, AddEntityFlags = noop }
end
Vector = setmetatable({Zero = {X = 0, Y = 0}}, {__call = function(_, x, y) return {X = x, Y = y} end})
GridEntityType = { GRID_POOP = 14, GRID_ROCK = 2 }
EntityFlag = { FLAG_NO_DAMAGE_BLINK = 1 }
ModCallbacks = { MC_POST_RENDER = 1 }
Isaac = { GetPlayer = function(i) return players[i] end, GetRoomEntities = function() return {} end,
    DebugString = noop, AddCallback = noop }
Game = function() return { GetNumPlayers = function() return 2 end, GetRoom = function() return room end } end
_IsaacLanTest = { host = """
        + lua_support.literal(host)
        + """, port = "1234" }
_IsaacLanFrame = function() return status end
local before
_IsaacLan = {
    net_gate = function(_, callback) before = callback end, test_gamepad = noop,
    rooms_positions = function() return locations end,
    rooms_with_player = function(_, fn) fn(); return true end,
    api_info = function() return { ready = 1 } end,
}
local files = io
io = nil
local fixture = dofile("""
        + lua_support.literal(str(ROOT / "tests/state_motion.lua"))
        + """)
io = files
if _IsaacLanTest.host then
    _IsaacLan.net_gate(noop, noop, noop, noop, noop, noop)
    before(0, 0, "")
    assert(door.locked and not door.opened, "Motion fixture left its exit traversable")
end
_IsaacLanFrame()
locations["1"].index = 85
status.verified = 12
local ok, message = pcall(_IsaacLanTest.host and function() before(12, 0, "") end or _IsaacLanFrame)
assert(not ok and message:find("Motion fixture left its room", 1, true),
    "Room drift was misreported as a movement/grid regression: " .. tostring(message))
locations["1"].index = 84
fixture.cleanup()
assert(not door.locked and door.opened, "Motion fixture left a locked exit for the next scenario")
""",
        tmp_path,
    )


@pytest.mark.parametrize("host", [True, False])
def test_recovery_fixture_emits_complete_input_and_releases_movement(tmp_path, host):
    run_lua(
        """
local input, tick = assert(_IsaacLanTestInput), 0
local function noop() end
local players = {}
for slot = 0, 1 do
    players[slot] = {
        ControllerIndex = slot + 1,
        GetPlayerType = function() return slot == 0 and 1 or 0 end,
        GetNumCoins = function() return 0 end,
        AddCoins = noop, AddCollectible = noop,
    }
end
Game = function() return {
    GetRoom = function() return {GetCenterPos = function() return {} end} end,
    GetLevel = function() return {GetCurrentRoomIndex = function() return 84 end} end,
} end
_IsaacLan = {
    net_phases = function() return {} end,
    net_gate = function(capture) return capture end,
    rooms_heads = function() return {["0"] = 0, ["1"] = 1} end,
    api_info = function() return {nowMs = 0} end,
}
_IsaacLanFrame = noop
_IsaacLanStatus = function() return {verified = tick} end
CollectibleType, ModCallbacks = {}, {}
EntityType = {ENTITY_PLAYER = 1}
Isaac = {AddCallback = noop, DebugString = noop, GetPlayer = function(slot) return players[slot] end}
_IsaacLanTest = {host = """
        + lua_support.literal(host)
        + """, port = "1234"}
dofile("""
        + lua_support.literal(str(ROOT / "tests/state_client_recovery.lua"))
        + """)
local capture = _IsaacLan.net_gate()
for _, time in ipairs({0, 1, 19, 20, 21, 40, 100}) do
    tick = time
    local frame = input.decode(capture())
    for action, value in pairs(frame.values) do
        local moving = time < 20 and action == (_IsaacLanTest.host and 0 or 2)
        assert(value == (moving and input.maxValue or 0), "Recovery movement changed")
    end
    assert(frame.triggered == 0 and not frame.pointer.active)
    assert(frame.pointer.x == 0 and frame.pointer.y == 0)
end
""",
        tmp_path,
    )


def test_field_scenario_announces_the_ready_lobby_before_gameplay(tmp_path):
    run_lua(
        """
local status = { phase = 0, players = 1, verified = 0 }
local ready, hosted = false, false
_IsaacLanTest = { host = true, port = "1234" }
_IsaacLan = { net_gate = function() end, test_gamepad = function() end }
_IsaacLanFrame = function() return status end
_IsaacLanModules = { ["sync/codec"] = {}, ["sync/entity_schema"] = function() return {} end }
createEntityFieldsProbe = function() return function() error("Probe ran in lobby") end end
Isaac = { DebugString = function(message)
    assert(hosted and message == "LAN_NETWORK MENU_READY")
    ready = true
end }
function _IsaacLanCommand(action, value)
    if action == "host" then
        assert(value == "1234" and not hosted)
        hosted, status.phase = true, 2
    else
        assert(action == "choose" and value == "0:1" and ready)
    end
end
local scenario = dofile("""
        + lua_support.literal(str(ROOT / "tests/state_entity_fields.lua"))
        + """)
for _ = 1, 300 do _IsaacLanFrame() end
assert(ready and not scenario.done())
""",
        tmp_path,
    )


@pytest.mark.parametrize("role", ["host", "client"])
def test_pause_scenario_is_pending_during_startup(tmp_path, role):
    role_file = tmp_path / "role.txt"
    role_file.write_text(role)
    source = (
        lua_support.support()
        + """
local registered = {}
Isaac = {
    AddCallback = function(_, _, callback) registered[callback] = true end,
    RemoveCallback = function(_, _, callback) registered[callback] = nil end,
}
ModCallbacks = { MC_POST_GAME_STARTED = 1, MC_PRE_GAME_EXIT = 2 }
_IsaacLanTest = { port = "1234" }
_IsaacLan = {
    pause_menu_state = function() error("Pause menu read during startup") end,
    net_gate = function() end,
    test_gamepad = function(buttons) assert(buttons == 0) end,
    api_info = function() return { nowMs = 0 } end,
}
local status = { phase = 0, scene = 1, prepared = false }
_IsaacLanFrame = function() return status end
local open = io.open
io.open = function(path, mode)
    if path == "./lan-test-role.txt" then path = ROLE_FILE end
    return open(path, mode)
end
local scenario = createScenario(FACTORY)
assert(scenario.done() == false)
for _ = 1, 3 do
    assert(scenario.call(_IsaacLanFrame) == status)
    assert(scenario.done() == false)
end
assert(next(registered))
scenario.cleanup()
assert(not next(registered))
"""
    )
    fixture = lua_support.factory(
        "state_pause_menu.lua",
        prelude="local pausePulses = 8\nlocal pauseCoordination = "
        + lua_support.literal(str(tmp_path)),
    )
    run_lua(
        source.replace("ROLE_FILE", lua_support.literal(str(role_file))).replace(
            "FACTORY", fixture
        ),
        tmp_path,
    )


def test_inventory_covers_every_fixture_and_executor():
    catalog = inventory()
    assert {entry["script"] for entry in catalog["fixtures"]} == {
        path.name for path in (ROOT / "tests").glob("state_*.lua")
    }
    entries = {entry["entry"] for entry in catalog["suites"]}
    assert {str(path.relative_to(ROOT)) for path in (ROOT / "tools").glob("run_*.py")} - {
        "tools/run_network_engine.py"
    } <= entries
    assert all((ROOT / path).is_file() for path in entries)
    assert "tools/run_network_engine.py" not in entries
    assert {"tools/manual_gameplay.py", "tools/validate_replica.py"} <= entries
    with pytest.raises(ValueError, match="Unknown"):
        suite_command("missing", [])


def test_discovery_tracks_added_renamed_and_deleted_files(tmp_path, monkeypatch):
    monkeypatch.setattr(discovery, "ROOT", tmp_path)
    runners, fixtures = tmp_path / "tools", tmp_path / "tests"
    runners.mkdir()
    fixtures.mkdir()
    for name in ("run_zeta.py", "run_network_engine.py", "helper.py"):
        (runners / name).write_text("raise RuntimeError('discovery must not import runners')")
    for name in ("state_zeta.lua", "state_alpha.lua", "helper.lua"):
        (fixtures / name).write_text("error('discovery must not execute fixtures')")
    (fixtures / "state_directory.lua").mkdir()
    assert inventory() == {
        "requires_game": True,
        "suites": [{"id": "zeta", "entry": "tools/run_zeta.py"}],
        "fixtures": [
            {"id": "alpha", "script": "state_alpha.lua"},
            {"id": "zeta", "script": "state_zeta.lua"},
        ],
    }
    (fixtures / "state_zeta.lua").unlink()
    (fixtures / "state_alpha.lua").rename(fixtures / "state_new_case.lua")
    (runners / "run_zeta.py").rename(runners / "run_new_case.py")
    assert inventory()["fixtures"] == [{"id": "new-case", "script": "state_new_case.lua"}]
    assert suite_command("new-case", ["--case", "selected"]) == [
        sys.executable,
        str(runners / "run_new_case.py"),
        "--case",
        "selected",
    ]
    with pytest.raises(ValueError, match="Unknown"):
        suite_command("zeta", [])
    (runners / "run_new_case.py").unlink()
    assert inventory()["suites"] == []
    with pytest.raises(ValueError, match="Unknown"):
        suite_command("new-case", [])


@pytest.mark.parametrize("action", ["list", "plan"])
def test_listing_and_planning_never_start_processes(tmp_path, monkeypatch, capsys, action):
    import engine_test

    monkeypatch.setattr(discovery, "ROOT", tmp_path)
    (tmp_path / "tools").mkdir()
    script = tmp_path / "tools/run_new_suite.py"
    script.write_text("raise RuntimeError('discovery must not import runners')")

    def forbidden(*args, **kwargs):
        raise AssertionError("Discovery started a subprocess")

    monkeypatch.setattr(subprocess, "Popen", forbidden)
    monkeypatch.setattr(subprocess, "run", forbidden)
    monkeypatch.setattr(
        sys,
        "argv",
        ["engine_test.py", action]
        + (["new-suite", "--", "--case", "mom"] if action == "plan" else []),
    )
    assert engine_test.main() == 0
    result = json.loads(capsys.readouterr().out)
    if action == "plan":
        assert result["game_started"] is False
        assert result["command"][:2] == [sys.executable, str(script)]
        assert result["command"][-2:] == ["--case", "mom"]
    else:
        assert result["requires_game"] is True
        assert result["suites"] == [{"id": "new-suite", "entry": "tools/run_new_suite.py"}]


def test_interrupted_child_gets_time_to_cleanup():
    child = (
        "import signal,time,sys\n"
        "def stop(*args):\n print('cleaned',flush=True)\n sys.exit(0)\n"
        "signal.signal(signal.SIGTERM,stop)\nprint('ready',flush=True)\n"
        "while True: time.sleep(0.1)\n"
    )
    with pytest.raises(KeyboardInterrupt):
        with engine_process(
            [sys.executable, "-u", "-c", child], stdout=subprocess.PIPE, text=True
        ) as process:
            assert process.stdout.readline().strip() == "ready"
            raise KeyboardInterrupt()
    assert process.returncode == 0
    assert process.stdout.read().strip() == "cleaned"
    process.stdout.close()


@pytest.fixture
def protection(tmp_path, monkeypatch):
    monkeypatch.setattr(lab_profile, "idle", lambda labs: None)
    labs = [tmp_path / role for role in ("host", "client")]
    for lab in labs:
        (lab / "profile").mkdir(parents=True)
        (lab / ".isaac-lan-lab").touch()
        (lab / "profile/save.dat").write_bytes(b"original")
    output = tmp_path / "report"
    output.mkdir()
    protected = lab_profile.ProtectedLabs(labs, output)
    for lab in labs:
        (lab / "profile/save.dat").write_bytes(b"fixture")
    return protected, output


@pytest.mark.parametrize("failure", [None, AssertionError, RuntimeError, KeyboardInterrupt])
def test_outcome_and_restore_survive_failures(protection, failure):
    protected, output = protection
    report = {"passed": True}
    try:
        try:
            if failure:
                raise failure("injected")
        finally:
            finish_run(protected, report, output)
    except BaseException as error:
        assert type(error) is failure
    assert all((lab / "profile/save.dat").read_bytes() == b"original" for lab in protected.labs)
    assert report["restored"] is True
    expected = "passed" if failure is None else "failed" if failure is AssertionError else "error"
    assert report["status"] == expected
    assert json.loads((output / "report.json").read_text()) == report
    case = ET.parse(output / "junit.xml").find("testcase")
    assert (case.find("failure") is not None) == (expected == "failed")
    assert (case.find("error") is not None) == (expected == "error")


def test_restore_failure_cannot_be_reported_as_pass(protection, monkeypatch):
    protected, output = protection

    def busy(labs):
        raise RuntimeError("game still running")

    monkeypatch.setattr(lab_profile, "idle", busy)
    report = {"passed": True}
    finish_run(protected, report, output)
    assert not report["passed"] and not report["restored"] and report["status"] == "error"
    assert "game still running" in report["restoration_error"]
    assert all((lab / "profile/save.dat").read_bytes() == b"fixture" for lab in protected.labs)


def test_child_stops_before_data_is_restored(protection, monkeypatch):
    protected, output = protection
    events = []

    class Child:
        running = True

        def poll(self):
            return None if self.running else 0

        def terminate(self):
            events.append("terminate")

        def wait(self, timeout):
            events.append("wait")
            self.running = False

    child = Child()

    def idle(labs):
        assert not child.running
        events.append("restore")

    monkeypatch.setattr(lab_profile, "idle", idle)
    finish_run(protected, {"passed": False}, output, process=child)
    assert events == ["terminate", "wait", "restore"]


def test_unfinished_backend_never_restores_live_data(protection):
    protected, output = protection

    class Child:
        def poll(self):
            return None

        def terminate(self):
            pass

        def wait(self, timeout):
            raise subprocess.TimeoutExpired("owned backend", timeout)

    report = {"passed": True}
    finish_run(protected, report, output, process=Child())
    assert report["status"] == "error" and not report["restored"]
    assert all((lab / "profile/save.dat").read_bytes() == b"fixture" for lab in protected.labs)


def test_transport_completion_without_suite_assertions_is_not_a_pass(protection):
    protected, output = protection
    report = {"engine": {"pass": True}}
    finish_run(protected, report, output)
    assert report["status"] == "failed" and not report["passed"]


@pytest.mark.parametrize("caught", [True, False])
def test_backend_cleanup_error_never_restores_live_data(protection, caught):
    protected, output = protection
    report = {"passed": True}
    try:
        try:
            raise BackendCleanupError("still shutting down")
        except BackendCleanupError as error:
            if not caught:
                raise
            report["error"], report["error_type"] = str(error), type(error).__name__
        finally:
            finish_run(protected, report, output)
    except BackendCleanupError:
        pass
    assert report["status"] == "error" and not report["restored"]
    assert all((lab / "profile/save.dat").read_bytes() == b"fixture" for lab in protected.labs)


@pytest.fixture
def fake_scenarios(tmp_path, monkeypatch):
    source = """
local config = _IsaacLanTest
observed[#observed + 1] = config
local owner = {}
Isaac.AddCallback(owner, 1, function() end)
_IsaacLanFrame = function() return state end
return {
    done = function() return complete end,
    cleanup = function() cleanups = cleanups + 1 end,
}
"""
    tests = tmp_path / "tests"
    (tests / "support").mkdir(parents=True)
    for relative in ("support/scenario.lua", "support/input.lua", "special_suite_driver.lua"):
        shutil.copyfile(ROOT / "tests" / relative, tests / relative)
    for name in (
        "greed",
        "endings",
        "lanbot",
        "lanbot_campaign",
        "lanbot_spiders",
        "lanbot_greed",
        "local_hud",
        "guest_visuals",
        "character_revival",
        "item_room_effects",
        "side_routes",
    ):
        (tests / f"state_{name}.lua").write_text(source)
    monkeypatch.setattr(lua_support, "ROOT", tmp_path)
    return tmp_path


@pytest.mark.parametrize(
    "cases,first_floor",
    [
        (["greed", "greedier"], False),
        (["greed", "greedier", "endings"], True),
        (["lanbot", "lanbot-campaign", "lanbot-spiders", "lanbot-greed"], False),
        (["campaign", "ascent-compat"], False),
        (["local-hud", "guest-visuals", "character-revival"], False),
        (["item-room-effects", "abyss-escape", "beast-layering"], False),
    ],
)
def test_built_suites_execute_options_and_cleanup(fake_scenarios, cases, first_floor):
    output = fake_scenarios / "suite.lua"
    build_special(output, cases, first_floor=first_floor)
    run_lua(
        """
observed, cleanups, removed, started, now = {}, 0, 0, 0, 0
state = { phase = 3, scene = 2, prepared = true }
complete = false
Options = {}
_IsaacLanTest = { host = true, port = "1234" }
_IsaacLanFrame = function() return state end
_IsaacLan = {
    net_gate = function() end,
    test_gamepad = function(buttons) assert(buttons == 0) end,
    api_info = function() return { nowMs = now } end,
    net_command = function() state = { phase = 0, scene = 1, prepared = false }; return true end,
}
Isaac = {
    AddCallback = function() started = started + 1 end,
    RemoveCallback = function() removed = removed + 1 end,
    DebugString = function() end,
}
dofile("""
        + lua_support.literal(str(output))
        + """)
local expected = """
        + lua_support.literal(cases)
        + """
assert(#observed == 0)
_IsaacLanFrame()
assert(#observed == 0, "Fixture activated before the native menu")
state = { phase = 0, scene = 1, prepared = false }
_IsaacLanFrame()
state = { phase = 3, scene = 2, prepared = true }
for index, name in ipairs(expected) do
    assert(#observed == index and observed[index].route == (name == "abyss-escape" and "knife" or name))
    assert(observed[index].abyssEscape == (name == "abyss-escape"))
    assert(observed[index].beastLayering == (name == "beast-layering"))
    if name == "beast-layering" then
        assert(observed[index].homeOnly and observed[index].endingRoutes[1] == "ascent")
    end
    assert(observed[index].firstFloor == (name == "endings" and """
        + lua_support.literal(first_floor)
        + """))
    assert(observed[index].greedCampaign == (name == "greed" or name == "greedier"))
    if name == "campaign" then assert(observed[index].endingRoutes[1] == "lamb") end
    if name == "ascent-compat" then assert(observed[index].endingRoutes[1] == "ascent") end
    complete = true
    _IsaacLanFrame()
    assert(cleanups == index and removed == index)
    now = now + 2100
    _IsaacLanFrame()
    now = now + 1100
    _IsaacLanFrame()
    state = { phase = 3, scene = 2, prepared = true }
    complete = false
end
assert(started == #expected and cleanups == #expected)
assert(_IsaacLanTest.route == nil)
""",
        fake_scenarios,
    )


def test_special_suite_rejects_invalid_selection(tmp_path):
    output = tmp_path / "suite.lua"
    for cases in ([], ["missing"], ["motion", "motion"]):
        with pytest.raises(ValueError, match="distinct known"):
            build_special(output, cases)
    with pytest.raises(ValueError, match="requires the six ending routes"):
        build_special(output, ["greed"], first_floor=True)
    assert not output.exists()


@pytest.mark.parametrize("bundled", [False, True])
def test_ending_builder_passes_selected_routes_without_source_rewriting(fake_scenarios, bundled):
    output = fake_scenarios / "ending.lua"
    build_endings(output, ["mother", "lamb"], first_floor=True)
    if bundled:
        output.write_text(lua_support.bundle_input(output.read_text()))
    run_lua(
        """
observed = {}
_IsaacLanTest = {}
Isaac = { AddCallback = function() end }
dofile("""
        + lua_support.literal(str(output))
        + """)
assert(observed[1].firstFloor)
assert(#observed[1].endingRoutes == 2)
assert(observed[1].endingRoutes[1] == "mother" and observed[1].endingRoutes[2] == "lamb")
""",
        fake_scenarios,
    )


@pytest.mark.parametrize(
    "mode", ["normal", "redirect", "dimension", "timeout", "mother", "doorway"]
)
def test_ending_boss_entry_confirms_native_destination(tmp_path, mode):
    run_lua(
        "local mode = "
        + lua_support.literal(mode)
        + """
local function noop() end
local moves, messages, before = {}, {}, nil
local stage, kind, roomIndex, dimension = 1, 0, 84, 0
local expectedSlot = mode == "mother" and 0 or 1
local player = {
    IsDead = function() return false end,
    IsCoopGhost = function() return false end,
    SetMinDamageCooldown = noop, AddEntityFlags = noop, AddCollectible = noop,
}
Vector = setmetatable({Zero = {}}, {__call = function(_, x, y) return {X = x, Y = y} end})
local level = {
    GetStage = function() return stage end,
    GetStageType = function() return kind end,
    SetStage = function(_, nextStage, nextKind) stage, kind = nextStage, nextKind end,
    GetRooms = function() return {Size = 1, Get = function()
        return {SafeGridIndex = 135, Data = {Type = 5}}
    end} end,
}
Game = function() return {
    GetLevel = function() return level end,
    GetRoom = function() return {
        GetType = function() return roomIndex == 135 and 5 or 1 end,
        GetCenterPos = function() return Vector(320, 280) end,
    } end,
    SetStateFlag = noop, StartStageTransition = noop,
} end
_IsaacLan = {
    rooms_ready = function() return true end,
    rooms_with_player = function(_, callback) callback(); return true end,
    rooms_heads = function() return {["0"] = 0, ["1"] = 1} end,
    rooms_positions = function() return {
        ["0"] = {index = roomIndex, dimension = dimension},
        ["1"] = {index = roomIndex, dimension = dimension},
    } end,
    rooms_move = function(slot, index, dim)
        assert(slot == expectedSlot and index == 135 and dim == 0)
        moves[#moves + 1] = index
        -- Native entry commits after the queued request, not inside it.
        return true
    end,
    net_gate = function(_, callback) before = callback end,
}
Isaac = {
    AddCallback = noop, GetPlayer = function() return player end,
    DebugString = function(message) messages[#messages + 1] = message end,
    GetRoomEntities = function() return {} end,
}
EntityType, EntityFlag, ModCallbacks, PickupVariant, GameStateFlag = {}, {}, {}, {}, {}
RoomType, StageType = {ROOM_BOSS = 5}, {STAGETYPE_REPENTANCE = 4}
_IsaacLanFrame = noop
_IsaacLanTest = {
    host = true, port = "1234", campaign = mode ~= "mother",
    endingRoutes = {mode == "mother" and "mother" or "blue-baby"},
}
dofile("""
        + lua_support.literal(str(ROOT / "tests/state_endings.lua"))
        + """)
_IsaacLan.net_gate(noop, noop, noop, noop, noop, noop)
local function saw(fragment)
    for _, message in ipairs(messages) do
        if message:find(fragment, 1, true) then return true end
    end
    return false
end
before(31)
if mode == "mother" then stage, kind = 8, 4 end
before(172)
assert(#moves == 1 and not saw("STEP boss-fight"))
before(202)
assert(#moves == 1, "Retried a still-pending native entry")
roomIndex = (mode == "redirect" or mode == "timeout") and 148 or 135
dimension = mode == "dimension" and 1 or 0
if mode == "doorway" then
    player.Position, player.Velocity = Vector(320, 440), Vector(0, 1)
end
before(203)
if mode == "timeout" then
    local ok, message = pcall(function()
        for tick = 234, 1500, 31 do before(tick) end
    end)
    assert(not ok and message:find("Boss entry kept redirecting", 1, true), message)
    assert(not saw("STEP boss-fight"), "Fought in the wrong room")
else
    local redirected = mode == "redirect" or mode == "dimension"
    assert(#moves == (redirected and 2 or 1))
    assert(saw("BOSS_ENTRY_REDIRECT") == redirected)
    if redirected then
        roomIndex, dimension = 135, 0
        before(234)
    elseif mode == "mother" then
        before(213)
        assert(player.Position.X == 320 and player.Position.Y == 280)
        -- The native hole moves Mother combat into another arena.
        roomIndex = -10
    end
    before(redirected and 334 or 303)
    assert(saw("STEP boss-fight"), "Did not advance after confirmed arrival")
    assert(#moves == (redirected and 2 or 1), "Retried an already-confirmed entry")
    if mode == "doorway" then
        assert(player.Position.Y < 400 and player.Velocity == Vector.Zero,
            "Scripted combat left the entrant drifting against the exit door")
    end
end
""",
        tmp_path,
    )


@pytest.mark.parametrize("route", ["lamb", "blue-baby", "ascent"])
@pytest.mark.parametrize("pickup_state", ["owned", "pedestal", "missing", "other-player"])
def test_ending_photo_accepts_native_pickup_before_loot_scan(tmp_path, route, pickup_state):
    run_lua(
        "local route, pickupState = "
        + lua_support.literal(route)
        + ", "
        + lua_support.literal(pickup_state)
        + """
local function noop() end
local before, stage, roomIndex = nil, 1, 84
local messages, entities = {}, {}
local photo = route == "lamb" and 328 or 327
local function player(owned)
    return {
        IsDead = function() return false end,
        IsCoopGhost = function() return false end,
        SetMinDamageCooldown = noop, AddEntityFlags = noop,
        HasCollectible = function(_, id) return owned and id == photo end,
    }
end
local players = {[0] = player(pickupState == "other-player"), [1] = player(pickupState == "owned")}
Vector = setmetatable({Zero = {}}, {__call = function(_, x, y) return {X = x, Y = y} end})
EntityPtr = function(entity) return {Ref = entity} end
local level = {
    GetStage = function() return stage end,
    GetStageType = function() return 0 end,
    GetRooms = function() return {Size = 1, Get = function()
        return {SafeGridIndex = 135, Data = {Type = 5}}
    end} end,
}
Game = function() return {
    GetLevel = function() return level end,
    GetRoom = function() return {
        GetType = function() return roomIndex == 135 and 5 or 1 end,
        IsClear = function() return true end,
        GetCenterPos = function() return Vector(320, 280) end,
    } end,
} end
_IsaacLan = {
    rooms_ready = function() return true end,
    rooms_with_player = function(_, callback) callback(); return true end,
    rooms_heads = function() return {["0"] = 0, ["1"] = 1} end,
    rooms_positions = function() return {["1"] = {index = roomIndex, dimension = 0}} end,
    rooms_move = function(slot, index)
        assert(slot == 1 and index == 135)
        roomIndex = index
        return true
    end,
    net_gate = function(_, callback) before = callback end,
}
Isaac = {
    AddCallback = noop, GetPlayer = function(index) return players[index] end,
    DebugString = function(message) messages[#messages + 1] = message end,
    GetRoomEntities = function() return entities end,
}
EntityType, EntityFlag, ModCallbacks, GameStateFlag = {}, {}, {}, {}
PickupVariant, RoomType = {PICKUP_COLLECTIBLE = 100}, {ROOM_BOSS = 5}
_IsaacLanFrame = noop
_IsaacLanTest = {host = true, port = "1234", campaign = true, endingRoutes = {route}}
dofile("""
        + lua_support.literal(str(ROOT / "tests/state_endings.lua"))
        + """)
_IsaacLan.net_gate(noop, noop, noop, noop, noop, noop)
before(31)
stage = 6
before(172)
before(303)
local boss = {
    Type = 45, Variant = 0, InitSeed = 1, HitPoints = 645, MaxHitPoints = 645,
    FrameCount = 0, State = 1, V2 = {X = 0},
    ToNPC = function(self) return self end,
    IsBoss = function() return true end,
    GetSprite = function() return {GetAnimation = function() return "Idle" end} end,
}
entities = {boss}
before(424)
entities = pickupState == "pedestal" and {{
    Type = 5, Variant = 100, SubType = photo, Position = Vector(320, 280),
    ToNPC = function() end, ToPickup = function(self) return self end,
    Exists = function() return false end,
}} or {}
before(525)
local advanced = false
for _, message in ipairs(messages) do
    if message:find("STEP photo ", 1, true) then advanced = true end
end
assert(advanced == (pickupState == "owned" or pickupState == "pedestal"),
    "Photo acquisition must accept earlier native pickup and require guest ownership or pedestal")
if not advanced then
    local ok, message = pcall(function() before(1924) end)
    assert(not ok and message:find("Route stalled at boss-loot", 1, true), message)
end
""",
        tmp_path,
    )


@pytest.mark.parametrize(
    "route,beam_direction",
    [("lamb", direction) for direction in ("none", "right", "left", "above", "below", "chest")]
    + [("blue-baby", "chest"), ("blue-baby", "light")],
)
def test_ending_exit_approach_preserves_native_contact(tmp_path, route, beam_direction):
    run_lua(
        "local beamDirection = "
        + lua_support.literal(beam_direction)
        + "\nlocal route = "
        + lua_support.literal(route)
        + """
local function noop() end
local before, collect, metadata, stage, kind, roomIndex = nil, nil, nil, 1, 0, 84
local entities, messages = {}, {}
local isChest = beamDirection == "chest"
local isLight = beamDirection == "light"
local vector = {}
vector.__index = vector
function vector.__add(a, b) return Vector(a.X + b.X, a.Y + b.Y) end
function vector.__sub(a, b) return Vector(a.X - b.X, a.Y - b.Y) end
function vector.__mul(a, b) return Vector(a.X * b, a.Y * b) end
function vector:LengthSquared() return self.X * self.X + self.Y * self.Y end
function vector:Normalized() return self * (1 / math.sqrt(self:LengthSquared())) end
Vector = setmetatable({}, {__call = function(_, x, y)
    return setmetatable({X = x, Y = y}, vector)
end})
Vector.Zero = Vector(0, 0)
local players = {}
local extraAnimationFinished = true
for slot = 0, 1 do players[slot] = {
    IsDead = function() return false end, IsCoopGhost = function() return false end,
    IsExtraAnimationFinished = function() return extraAnimationFinished end,
    SetMinDamageCooldown = noop, AddEntityFlags = noop,
    Position = Vector(320, 320),
} end
local player = players[1]
local exit = Vector(320, 320)
local beam = ({right = Vector(80, 0), left = Vector(-80, 0),
    above = Vector(0, -80), below = Vector(0, 80)})[beamDirection]
beam = isLight and exit + Vector(80, 0) or beam and exit + beam
local level = {
    GetStage = function() return stage end, GetStageType = function() return kind end,
    GetRooms = function() return {Size = 1, Get = function()
        return {SafeGridIndex = 135, Data = {Type = 5}}
    end} end,
}
Game = function() return {
    GetLevel = function() return level end,
    GetRoom = function() return {
        GetType = function() return roomIndex == 135 and 5 or 1 end,
        IsClear = function() return true end,
        GetCenterPos = function() return Vector(320, 280) end,
        GetGridSize = function() return 1 end,
        GetGridEntity = function() return {Position = exit, GetType = function() return 17 end} end,
    } end,
} end
_IsaacLan = {
    rooms_ready = function() return true end,
    rooms_with_player = function(_, callback) callback(); return true end,
    rooms_heads = function() return {["0"] = 0, ["1"] = 1} end,
    rooms_positions = function() return {["1"] = {index = roomIndex, dimension = 0}} end,
    rooms_move = function(_, index) roomIndex = index; return true end,
    net_gate = function(_, callback, collector) before, collect = callback, collector end,
}
Isaac = {
    AddCallback = noop, GetPlayer = function(index) return players[index] end,
    DebugString = function(message) messages[#messages + 1] = message end,
    GetRoomEntities = function() return entities end,
}
EntityType, EntityFlag, ModCallbacks, PickupVariant, GameStateFlag = {ENTITY_EFFECT = 1000}, {}, {}, {PICKUP_BIGCHEST = 340}, {}
EffectVariant, GridEntityType, RoomType = {HEAVEN_LIGHT_DOOR = 39}, {GRID_TRAPDOOR = 17}, {ROOM_BOSS = 5}
EntityPtr = function(entity) return {Ref = entity} end
_IsaacLanState = {encode = function(value) metadata = value; return "" end}
_IsaacLanFrame = noop
_IsaacLanTest = {host = true, port = "1234", campaign = true, endingRoutes = {route}}
dofile("""
        + lua_support.literal(str(ROOT / "tests/state_endings.lua"))
        + """)
_IsaacLan.net_gate(noop, noop, function() return "body" end, noop, noop, noop)
before(31)
stage = isChest and 10 or 8
kind = isChest and route == "blue-baby" and 1 or 0
before(172)
before(303)
entities = {{
    Type = 78, Variant = 1, InitSeed = 1, HitPoints = 1, MaxHitPoints = 1,
    FrameCount = 0, State = 1, V2 = {X = 0},
    ToNPC = function(self) return self end, IsBoss = function() return true end,
    GetSprite = function() return {GetAnimation = function() return "Idle" end} end,
}}
before(424)
entities = isChest and {{
    Type = 5, Variant = 340, SubType = 0, Position = exit,
    ToNPC = noop, ToPickup = function(self) return self end,
    Exists = function() return true end, IsDead = function() return false end,
}} or beam and {{
    Type = 1000, Variant = 39, Position = beam, ToNPC = noop,
    Exists = function() return true end, IsDead = function() return false end,
}} or {}
before(525)
if isLight then
    player.Position = Vector(160, 220)
    before(526)
    assert((player.Position - beam):LengthSquared() == 60 * 60,
        "Light fixture did not back off before entering through normal movement")
    player.Position, player.Velocity = Vector(440, 320), Vector(-4, 0)
    before(560)
    collect(1, 560)
    assert(metadata[8] == 0 and player.Position.X == 440 and player.Velocity.X == -4,
        "Light approach replaced normal guest movement with repeated positioning")
    extraAnimationFinished = false
    before(561)
    collect(1, 561)
    assert(metadata[8] == -1 and player.Position.X == 440,
        "Light fixture kept moving the actor during the native entrance animation")
    stage, kind = 10, 1
    player.Position = Vector(160, 220)
    before(562)
    assert(player.Position.X == 160 and player.Position.Y == 220,
        "Reused the previous floor's entrance contact after arrival")
    return
end
if isChest then
    assert((players[0].Position - exit):LengthSquared() >= 80 * 80,
        "Host still overlaps the chest and resets its native cooldown")
    assert((player.Position - exit):LengthSquared() == 60 * 60,
        "Guest was teleported into the solid chest instead of approaching it")
    before(560)
    collect(1, 560)
    assert(metadata[8] == 0, "Guest did not receive normal input towards the chest")
    stage = 11
    before(561)
    assert(messages[#messages]:find("NATIVE_PHOTO_CHEST destination=11:", 1, true),
        "Did not observe the native photo chest destination")
    return
end
assert((player.Position - exit):LengthSquared() == 0, "Did not contact the native trapdoor")
for tick = 526, 614 do
    before(tick)
    if beam then
        assert((player.Position - beam):LengthSquared() > 30 * 30,
            "Trapdoor fixture contacted the adjacent Cathedral light")
    end
end
assert((player.Position - exit):LengthSquared() == 4 * 4,
    "Did not return to the trapdoor after its opening animation")
stage = 10
before(615)
assert(messages[#messages]:find("ARRIVED stage=10 type=0", 1, true),
    "Did not observe the native Sheol arrival")
""",
        tmp_path,
    )


@pytest.mark.parametrize("complete_first", [True, False, "invalid"])
def test_continuous_suite_requires_completion_and_preserves_absolute_ticks(
    tmp_path, monkeypatch, complete_first
):
    tests = tmp_path / "tests"
    tests.mkdir()
    shutil.copyfile(ROOT / "tests/gameplay_suite_driver.lua", tests / "gameplay_suite_driver.lua")
    for name in ("motion", "arrival"):
        (tests / f"state_{name}.lua").write_text(
            """
local name = """
            + lua_support.literal(name)
            + """
local frame = _IsaacLanFrame
_IsaacLanFrame = function()
    Isaac.DebugString("LAN_NETWORK PASS an intermediate checkpoint")
    return frame()
end
local gate = _IsaacLan.net_gate
_IsaacLan.net_gate = function(...) return gate(...) end
Isaac.AddCallback({}, 1, function() callbacks[name] = (callbacks[name] or 0) + 1 end)
return {
    done = function()
        if completed[name] == "invalid" then return nil end
        return completed[name] == true
    end,
    cleanup = function() cleaned[name] = (cleaned[name] or 0) + 1 end,
}
"""
        )
    monkeypatch.setattr(build_gameplay_suite, "SOURCE", tmp_path)
    output = tmp_path / "suite.lua"
    phases = build_gameplay_suite.build(output, ["motion", "arrival"])
    # Only the two bootstrap files are virtualized; production time mapping,
    # callback dispatch, completion and cleanup are executed from the driver.
    source = (
        """
completed, cleaned, callbacks = {}, {}, {}
local installed, removed, ticks = {}, 0, {}
local status = { verified = 0, phase = 3, prepared = true }
_IsaacLanTest = { host = false }
_IsaacLanFrame = function() return status end
_IsaacLanStatus = function() return status end
_IsaacLanCommand = function() end
_IsaacLan = { test_gamepad = function() end, net_gate = function(...) handlers = {...}; return true end }
Isaac = {
    DebugString = function() end,
    AddCallback = function(owner, id, fn) installed[#installed + 1] = fn end,
    RemoveCallback = function() removed = removed + 1 end,
}
local open = io.open
io.open = function(path, mode)
    if path == "./lan-test-role.txt" or path == "./lan-test-menu-port.txt" then
        return { read = function() return path:find("role") and "client" or "1234" end, close = function() end }
    end
    return open(path, mode)
end
dofile("""
        + lua_support.literal(str(output))
        + """)
io.open = open
local function noop() end
_IsaacLan.net_gate(noop, function(t) ticks[#ticks + 1] = t end, noop, noop, noop, noop)
status.verified = """
        + str(phases[0]["start"])
        + """
handlers[2](status.verified, 0, "")
_IsaacLanFrame()
installed[1]()
installed[2]()
assert(callbacks.motion == 1 and callbacks.arrival == nil)
assert(ticks[1] == status.verified, "Authority tick was converted twice")
completed.motion = """
        + lua_support.literal(complete_first)
        + """
local frameOK = pcall(_IsaacLanFrame)
if completed.motion == "invalid" then
    assert(not frameOK and cleaned.motion == 1 and cleaned.arrival == 1 and removed == 2)
    return
end
assert(frameOK)
status.verified = """
        + str(phases[1]["start"])
        + """
local ok = pcall(handlers[2], status.verified, 0, "")
assert(ok == """
        + lua_support.literal(complete_first)
        + """, "A PASS log must not substitute for completion")
if ok then
    assert(cleaned.motion == 1 and removed == 1)
    installed[1]()
    installed[2]()
    assert(callbacks.motion == 1 and callbacks.arrival == 1)
    assert(ticks[#ticks] == status.verified)
    completed.arrival = true
    status.verified = """
        + str(phases[1]["start"] + phases[1]["duration"] + 30)
        + """
    _IsaacLanFrame()
    assert(cleaned.arrival == 1 and removed == 2)
else
    assert(cleaned.motion == 1 and cleaned.arrival == 1 and removed == 2)
end
"""
    )
    run_lua(source, tmp_path)


def test_beast_observer_checks_native_layer_values_without_optional_globals(tmp_path):
    run_lua(
        """
EntityType = { ENTITY_BEAST = 951 }
local function entity(kind, variant, layer, z)
    return { Type = kind, Variant = variant, SortingLayer = layer,
        RenderZOffset = z, DepthOffset = 0, Exists = function() return true end }
end
local players = { [0] = entity(1, 0, 0, 0), [1] = entity(1, 0, 0, 0) }
local room = { entity(951, 0, -100, 0), entity(951, 10, 0, 0) }
Isaac = { GetRoomEntities = function() return room end }
local native = { api_with_local_view = function(fn) fn() return true end }
local probe = dofile("""
        + lua_support.literal(str(ROOT / "tests/fixtures/beast_layer_probe.lua"))
        + """)(native, function(slot, fn) fn(players[slot]) end, function() end)
local expected
for i = 1, 130 do expected = probe.capture(); probe.restore(expected) end
room[1].SortingLayer = 0
assert(not pcall(probe.restore, expected), "Missed background Beast ordering mismatch")
room[1].SortingLayer = -100
players[1].RenderZOffset = 100
assert(not pcall(probe.restore, expected), "Missed player render offset mismatch")
ButtonAction = { ACTION_LEFT = 0, ACTION_RIGHT = 1, ACTION_UP = 2, ACTION_DOWN = 3 }
native.rooms_ready = function() return true end
native.rooms_heads = function() return { ["0"] = 0, ["1"] = 1 } end
Isaac.GetPlayer = function(slot) return players[slot] end
players[0].Position = { X = 80, Y = 340 }
assert(probe.direction(0) == ButtonAction.ACTION_RIGHT)
players[0].Position.X = 298
for i = 1, 60 do assert(probe.direction(0) == -1) end
probe.finish(true)
""",
        tmp_path,
    )
