"""Manual handoff, real delay configuration and failure cleanup without launching games."""

import configparser
import fcntl
import shutil
import subprocess
from types import SimpleNamespace

import pytest

import lab_profile
import manual_dual as dual
from testing.lua import literal


@pytest.mark.parametrize(
    "name,expected",
    [
        ("以撒", "PLAYER_ISAAC"),
        ("Isaac", "PLAYER_ISAAC"),
        ("阿撒泻勒", "PLAYER_AZAZEL"),
        ("里以撒", "PLAYER_ISAAC_B"),
        ("tainted-isaac", "PLAYER_ISAAC_B"),
        ("PLAYER_CAIN", "PLAYER_CAIN"),
        ("拉撒路", "PLAYER_LAZARUS"),
        ("0", 0),
        ("41", 41),
    ],
)
def test_character_selection_uses_menu_names_and_runtime_enums(name, expected):
    assert dual.character(name) == expected


@pytest.mark.parametrize("name", ["no-such-character", "-1", "65536"])
def test_unknown_character_rejected_before_start(name):
    with pytest.raises(ValueError):
        dual.character(name)


@pytest.mark.parametrize("value", ["nan", "inf", "-1", "10001"])
def test_bad_latency_rejected(value):
    with pytest.raises(ValueError):
        dual.latency(value)


@pytest.fixture
def session(tmp_path, monkeypatch):
    labs = [tmp_path / (role + "-001") for role in dual.ROLES]
    for lab in labs:
        (lab / "game/mods/lan_native_internal_probe").mkdir(parents=True)
        (lab / "game/mods/real-mod").mkdir()
        (lab / "game/isaac-ng.exe").write_bytes(b"isolated game")
        (lab / ".isaac-lan-lab").touch()
        (lab / "virtual-input.test").write_text("previous fixture")
        (lab / "frontend-scenario.lua").write_text("previous startup")
        (lab / "game/manual-dual-ready.json").write_text('{"session":"stale","ready":true}')
        options = dual.log_path(lab).parent
        options.mkdir(parents=True)
        (options / "options.ini").write_text(
            "[Options]\nAcceptedPublicBeta_v1.9.7.17=1\nMusicEnabled=0\nMusicVolume=0\nSFXVolume=0.4\nCustomOption=keep\n"
        )
        (options / "persistentgamedata1.dat").write_bytes(b"personal progress")
    build, output = tmp_path / "build", tmp_path / "run"
    build.mkdir()
    output.mkdir()
    for name in ("isaac_lan_probe.dll", "isaac_lan_lab.exe"):
        (build / name).write_bytes(b"candidate")
    config = {
        "session": "new",
        "labs": list(map(str, labs)),
        "build": str(build),
        "characters": ["PLAYER_ISAAC", "PLAYER_AZAZEL"],
        "latency_ms": 80,
    }
    dual.write_json(output / "config.json", config)
    monkeypatch.setattr(dual, "idle", lambda labs: None)
    monkeypatch.setattr(lab_profile, "idle", lambda labs: None)
    monkeypatch.setattr(
        dual,
        "freeze_probe_logs",
        lambda lab, destination, pid: destination.mkdir(parents=True, exist_ok=True),
    )
    monkeypatch.setattr(dual, "choose_host_port", lambda: 29506)
    monkeypatch.setattr(dual.time, "sleep", lambda seconds: None)
    relays = []

    class Relay:
        def __init__(self, port, target, delay):
            self.listener = SimpleNamespace(getsockname=lambda: ("127.0.0.1", 51880))
            self.delay, self.closed, self.error = delay, False, None
            relays.append(self)

        def close(self):
            self.closed = True

        def settings(self):
            return {"delay_ms": self.delay}

    monkeypatch.setattr(dual, "DatagramRelay", Relay)
    closed, launches = [], []

    def launch(lab, role, output):
        assert not (lab / "virtual-input.test").exists()
        assert not (lab / "game/mods/real-mod/disable.it").exists()
        options = configparser.ConfigParser()
        options.read(dual.log_path(lab).parent / "options.ini")
        assert options["Options"]["MusicEnabled"] == "1"
        assert options["Options"]["MusicVolume"] == "0.2000"
        assert options["Options"]["SFXVolume"] == "0.4"
        assert options["Options"]["CustomOption"] == "keep"
        dual.write_json(
            lab / "game/manual-dual-ready.json", {"session": "new", "role": role, "ready": True}
        )
        process = {
            "pid": len(launches) + 10,
            "path": str(lab / "game/isaac-ng.exe"),
            "started": "123",
            "role": role,
        }
        launches.append(process)
        return process

    monkeypatch.setattr(dual, "launch", launch)
    monkeypatch.setattr(dual, "close_owned", lambda owned, output: closed.extend(owned))
    observed_ready = []

    def live(owned):
        if dual.read_json(output / "session.json").get("status") == "ready":
            assert all(not (lab / "frontend-scenario.lua").exists() for lab in labs)
            observed_ready.append(True)
            return []  # Simulate the user's normal close, after handoff.
        return owned

    monkeypatch.setattr(dual, "live_owned", live)
    return SimpleNamespace(
        labs=labs,
        output=output,
        relays=relays,
        closed=closed,
        launches=launches,
        launch=launch,
        observed_ready=observed_ready,
    )


def assert_restored(session):
    saved = dual.read_json(session.output / "backup.json")
    restored = dual.read_json(session.output / "restored.json")
    assert restored == {path: entry["before"] for path, entry in saved.items()}
    for lab in session.labs:
        assert (lab / "virtual-input.test").read_text() == "previous fixture"
        assert (lab / "frontend-scenario.lua").read_text() == "previous startup"
        assert not (lab / "frontend.test").exists()
        assert not (lab / "game/mods/lan_native_internal_probe/disable.it").exists()
        assert dual.read_json(lab / "game/manual-dual-ready.json")["session"] == "stale"


def test_manual_handoff_releases_startup_hook_and_restores_after_user_close(session):
    assert dual.supervise(session.output) == 0
    state = dual.read_json(session.output / "session.json")
    assert state["status"] == "closed" and state["restored"]
    assert session.observed_ready and not session.closed
    assert session.relays[0].delay == 40 and session.relays[0].closed
    assert_restored(session)


def test_second_launch_failure_closes_only_first_owned_process_and_restores(session, monkeypatch):
    def launch(lab, role, output):
        if role == "client":
            raise RuntimeError("second launch failed")
        return session.launch(lab, role, output)

    monkeypatch.setattr(dual, "launch", launch)
    assert dual.supervise(session.output) == 1
    assert [p["role"] for p in session.closed] == ["host"]
    assert dual.read_json(session.output / "session.json")["error"] == "second launch failed"
    assert session.relays[0].closed
    assert_restored(session)


def test_owned_stop_after_handoff_closes_both_and_restores(session, monkeypatch):
    def live(owned):
        if dual.read_json(session.output / "session.json").get("status") == "ready":
            (session.output / "stop").touch()
        return owned

    monkeypatch.setattr(dual, "live_owned", live)
    assert dual.supervise(session.output) == 0
    assert [process["role"] for process in session.closed] == ["host", "client"]
    assert_restored(session)


def test_concurrent_launcher_cannot_change_busy_lab(session):
    before = lab_profile.hashes(session.labs[0] / "profile")
    with (session.labs[0] / ".manual-dual.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert dual.supervise(session.output) == 1
    assert not session.launches and not session.relays
    assert lab_profile.hashes(session.labs[0] / "profile") == before
    assert not (session.output / "backup.json").exists()


def test_existing_game_is_not_closed_or_reconfigured(session, monkeypatch):
    def occupied(labs):
        raise RuntimeError("already running")

    monkeypatch.setattr(dual, "idle", occupied)
    assert dual.supervise(session.output) == 1
    assert not session.launches and not session.closed
    assert not (session.output / "backup.json").exists()


def test_stale_or_wrong_peer_handoff_is_not_readiness(session):
    assert dual.readiness(session.labs, "new") is None
    for lab in session.labs:
        dual.write_json(
            lab / "game/manual-dual-ready.json", {"session": "new", "role": "host", "ready": True}
        )
    assert dual.readiness(session.labs, "new") is None
    dual.write_json(
        session.labs[1] / "game/manual-dual-ready.json",
        {"session": "new", "role": "client", "error": "locked character"},
    )
    with pytest.raises(RuntimeError, match="locked character"):
        dual.readiness(session.labs, "new")


def test_reused_pid_with_changed_path_or_start_is_not_owned(monkeypatch):
    original = {"pid": 10, "path": "D:/owned/game.exe", "started": "100"}
    monkeypatch.setattr(
        dual,
        "processes",
        lambda: [dict(original, started="101"), dict(original, path="D:/other/game.exe")],
    )
    assert dual.live_owned([original]) == []


@pytest.mark.parametrize(
    "response,count", [("", 0), ("[]", 0), ('{"pid":1}', 1), ('[{"pid":1},{"pid":2}]', 2)]
)
def test_windows_process_json_handles_zero_one_and_two_processes(monkeypatch, response, count):
    monkeypatch.setattr(dual.subprocess, "run", lambda *a, **kw: SimpleNamespace(stdout=response))
    assert len(dual.processes()) == count
    assert all(isinstance(process, dict) for process in dual.processes())


def test_explicit_recovery_restores_dead_supervisor_backup(session, monkeypatch):
    assert dual.supervise(session.output) == 0
    for lab in session.labs:
        (dual.log_path(lab).parent / "persistentgamedata1.dat").write_bytes(b"interrupted test")
        (lab / "virtual-input.test").unlink()
    state = dual.read_json(session.output / "session.json")
    state.update(status="error", restored=False, supervisor_pid=-1)
    dual.write_json(session.output / "session.json", state)
    assert dual.recover(session.output)["restored"]
    assert_restored(session)


@pytest.mark.parametrize("mode", ["host", "client", "unavailable", "rejected", "wrong-body"])
def test_lua_bootstrap_uses_real_command_contract_and_relinquishes_control(tmp_path, mode):
    # The real command function returns nil, and raises on rejection. No input API is supplied.
    source = r"""
local mode = MODE
local phases = {idle=0, lobby=2, running=3, failed=4, waiting=9}
local status = {phase=0, slot=mode == "client" and 1 or 0, players=2,
    ready0=1, ready1=1, choice0=0, choice1=7, prepared=true, verified=2, ping1=84}
local captured, calls = nil, {}
package.preload.json = function()
    return {encode=function(value) captured=value; return "recorded" end}
end
PlayerType = {PLAYER_ISAAC=0, PLAYER_AZAZEL=7}
local selected = mode == "client" and 7 or 0
_IsaacLan = {net_phases=function() return phases end, rooms_ready=function() return true end,
    net_characters=function() return mode == "unavailable" and {99} or {0,7} end}
Game = function() return {GetNumPlayers=function() return 1 end,
    GetLevel=function() return {GetStage=function() return 1 end} end} end
Isaac = {GetPlayer=function() return {ControllerIndex=status.slot+1,
    GetPlayerType=function() return mode == "wrong-body" and 99 or selected end} end}
local function original() return status end
_IsaacLanFrame = original
_IsaacLanCommand = function(action, value)
    if mode == "rejected" then error("native rejection") end
    calls[#calls+1]={action,value}
    if action == "host" or action == "join" then status.phase=phases.lobby end
end
assert(loadfile(BOOTSTRAP))()({session="nonce",host=mode ~= "client",port=29506,
    character=selected == 0 and "PLAYER_ISAAC" or "PLAYER_AZAZEL"})
for _=1,370 do _IsaacLanFrame() end
if mode == "unavailable" or mode == "rejected" then
    assert(captured.error and _IsaacLanFrame == original)
else
    assert(calls[1][1] == (mode == "client" and "join" or "host"))
    assert(calls[2][1] == "choose" and calls[2][2] == selected .. ":1")
    if mode == "host" then assert(calls[3][1] == "start" and calls[3][2] == "RANDOM:0:0:7:0:0") end
    status.phase=phases.running
    _IsaacLanFrame()
    assert(captured.ready == (mode ~= "wrong-body"))
    assert(captured.session == "nonce" and captured.character == selected)
    assert(_IsaacLanFrame == original)
    local count=#calls
    for _=1,100 do _IsaacLanFrame() end
    assert(#calls == count)
end
assert(io.open("manual-dual-ready.json", "r")):close()
""".replace("MODE", literal(mode)).replace(
        "BOOTSTRAP", literal(str(dual.ROOT / "tools/manual_dual_bootstrap.lua"))
    )
    script = tmp_path / "check.lua"
    script.write_text(source)
    subprocess.run([shutil.which("lua5.3"), str(script)], cwd=tmp_path, check=True)
