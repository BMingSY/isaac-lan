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
from game_logs import log_path


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
        (["local-hud", "guest-visuals"], False),
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
    assert(#observed == index and observed[index].route == name)
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


def test_ending_builder_passes_selected_routes_without_source_rewriting(fake_scenarios):
    output = fake_scenarios / "ending.lua"
    build_endings(output, ["mother", "lamb"], first_floor=True)
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


@pytest.mark.parametrize("mode", ["normal", "redirect", "dimension", "timeout", "mother"])
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
end
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
