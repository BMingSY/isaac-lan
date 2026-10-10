"""Continuous outcomes and command sequences; virtual frames never sleep."""

import json
from pathlib import Path

from hypothesis import given, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, invariant, rule, run_state_machine_as_test
import pytest

pytestmark = pytest.mark.behavior


@pytest.mark.parametrize("name", ["near-door-stall", "obstacle-stall", "slow-offset-stall"])
def test_saved_stall_regressions(lua, name):
    trace = json.loads((Path(__file__).parent / "replays" / (name + ".json")).read_text())
    for entry in trace:
        result = lua.call(*entry["request"])
    assert result[4] == 1 and result[5] == 0 and result[6] == 0, result


def reset(
    lua,
    side=2,
    speed=260,
    radius=10,
    offset=0,
    distance=56,
    obstacle=False,
    mode="explore",
    style="balanced",
):
    return lua.call("bot_reset", side, speed, radius, offset, distance, obstacle, mode, style)


@pytest.mark.parametrize("side", range(4), ids=["left", "up", "right", "down"])
@pytest.mark.parametrize("style", ["aggressive", "balanced", "cautious"])
def test_crosses_each_door_and_clears_departure_input(lua, side, style):
    reset(lua, side=side, style=style)
    result = lua.call("bot_step", 300)
    assert result[4] == 1, f"Failed to cross doorway: {result}"
    assert result[5] == 0, f"Movement collided with the fixture wall: {result}"
    assert result[6] == 0, "Arrival frame carried old departure buttons"
    assert result[0] == "running" and result[7] == "0:2"


@pytest.mark.property
@given(
    side=st.integers(0, 3),
    speed=st.integers(160, 400),
    radius=st.integers(6, 16),
    offset=st.integers(-6, 6),
    distance=st.integers(50, 120),
)
def test_doorway_progress_across_movement_parameters(lua, side, speed, radius, offset, distance):
    reset(lua, side, speed, radius, offset, distance)
    result = lua.call("bot_step", 360)
    assert result[4] == 1 and result[6] == 0, result
    assert result[5] == 0, result


def test_routes_around_a_wall_before_crossing(lua):
    reset(lua, distance=360, obstacle=True)
    result = lua.call("bot_step", 900)
    assert result[4] == 1, f"Obstacle route stalled: {result}"
    assert result[5] == 0 and result[6] == 0, result


def test_hold_stays_in_room_for_many_frames(lua):
    reset(lua, mode="hold")
    result = lua.call("bot_step", 600)
    assert result[4] == 0 and result[7] == "0:1"
    assert result[2] == 0 and result[0] == "running"


def test_pause_resume_and_new_session_release_held_input(lua):
    reset(lua, distance=200)
    moving = lua.call("bot_step", 20)
    assert moving[1] and moving[2] != 0
    paused = lua.call("bot_command", "pause")[1]
    assert paused[0] == "paused" and not paused[1] and paused[2] == 0
    assert lua.call("bot_step", 10)[2] == 0
    lua.call("bot_command", "resume")
    assert lua.call("bot_step", 10)[1]
    changed = lua.call("bot_session", True, "replacement-run")
    assert changed[0] == "off" and not changed[1] and changed[2] == 0


@pytest.mark.parametrize("side", range(4))
@pytest.mark.parametrize("mode", ["run", "explore"])
def test_explores_room_graph_without_bouncing_or_premature_exit(lua, side, mode):
    lua.call("bot_rooms_reset", "graph", mode, side, 260)
    result = lua.call("bot_rooms_step", 1800)
    assert result[10:12] == [True, True], result
    assert result[0] == (4 if mode == "run" else 3), result  # No extra room transfers.
    assert result[1] == (1 if mode == "run" else 0), result


@pytest.mark.parametrize("side", range(4))
@pytest.mark.parametrize("speed", [160, 400])
def test_arrival_brakes_outward_inertia_and_leaves_door_in_hold(lua, side, speed):
    lua.call("bot_rooms_reset", "arrival", "hold", side, speed)
    result = lua.call("bot_rooms_step", 300)
    assert result[0] == 0 and result[5] == "a", result
    assert result[6] == "wait" and result[7] == "room_clear", result


def test_completes_multiple_buttons_in_an_uncleared_room(lua):
    lua.call("bot_rooms_reset", "buttons", "explore", 2, 260)
    result = lua.call("bot_rooms_step", 600)
    assert result[2] == 2 and result[7] == "exploration_complete", result


@pytest.mark.parametrize("speed", [160, 260, 400])
@pytest.mark.parametrize("scenario", ["timed", "timed-short"])
def test_learns_spike_window_and_crosses_without_damage(lua, speed, scenario):
    lua.call("bot_rooms_reset", scenario, "explore", 2, speed)
    result = lua.call("bot_rooms_step", 1200)
    assert result[2] == 1 and result[3] == 0, result


@pytest.mark.parametrize("mode", ["hold", "explore"])
def test_avoids_exit_contact_while_waiting_or_collecting(lua, mode):
    lua.call("bot_rooms_reset", "exit-pickup", mode, 2, 260)
    result = lua.call("bot_rooms_step", 600)
    assert result[1] == 0, result
    assert result[4] == (1 if mode == "explore" else 0), result


def test_incoming_projectile_is_avoided_over_many_frames(lua):
    lua.call("bot_rooms_reset", "dodge", "hold", 2, 260)
    result = lua.call("bot_rooms_step", 120)
    assert result[3] == 0, result


@pytest.mark.property
def test_bot_command_and_frame_sequences(lua):
    class BotMachine(RuleBasedStateMachine):
        def __init__(self):
            super().__init__()
            reset(lua, mode="hold")
            self.expected = "running"
            self.mode = "hold"
            self.style = "balanced"

        @rule(command=st.sampled_from(["on", "pause", "resume", "off"]))
        def command(self, command):
            lua.call("bot_command", command)
            if command == "on":
                self.expected = "running"
            elif command == "off":
                self.expected = "off"
            elif command == "pause" and self.expected != "off":
                self.expected = "paused"
            elif command == "resume" and self.expected != "off":
                self.expected = "running"

        @rule(mode=st.sampled_from(["hold", "explore", "run"]))
        def change_mode(self, mode):
            lua.call("bot_command", "mode " + mode)
            self.mode = mode

        @rule(style=st.sampled_from(["aggressive", "balanced", "cautious"]))
        def change_style(self, style):
            lua.call("bot_command", "style " + style)
            self.style = style

        @rule(frames=st.integers(1, 15))
        def advance(self, frames):
            lua.call("bot_step", frames)

        @invariant()
        def ownership_and_configuration_are_consistent(self):
            value = lua.call("bot_command", "status")[1]
            assert value[0] == self.expected
            assert value[12:14] == [self.mode, self.style]
            if self.expected != "running":
                assert not value[1] and value[2] == 0

    run_state_machine_as_test(BotMachine)
