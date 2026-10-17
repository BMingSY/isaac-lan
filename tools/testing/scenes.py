"""Build native client scenes with explicit lifecycle and output parameters."""

from testing.lua import factory, write_suite
import csv
import statistics


def build_scene_suite(output):
    write_suite(
        output,
        [
            factory("state_scene_performance.lua"),
            factory(
                "state_bag_transitions.lua",
                options={"sceneOutput": "./lan-test-digest-bag-transitions.csv"},
            ),
        ],
    )


def measure_bag_transitions(path):
    rows = list(csv.DictReader(path.open()))
    report = []
    for cycle in range(8):
        for action, offset in (("raise", 6), ("lower", 42)):
            start = 216 + cycle * 72 + offset
            samples = [r for r in rows if start <= int(r["tick"]) < start + 12]
            assert len(samples) >= 15, f"Missing bag transition {cycle}: {action}"
            assert any((r["holding"] == "true") == (action == "raise") for r in samples)
            intervals = sorted(float(r["interval_ms"]) for r in samples)
            result = {
                "cycle": cycle,
                "action": action,
                "moving": cycle < 6,
                "eid": samples[-1]["phase"],
                "samples": len(samples),
                "prediction_resets": sum(int(r["prediction_resets"]) for r in samples),
                "max_interval_ms": max(intervals),
                "p95_interval_ms": intervals[int(len(intervals) * 0.95)],
            }
            assert result["prediction_resets"] == 0, result
            assert result["max_interval_ms"] < 50, result
            if cycle < 6:
                direction = 1 if action == "raise" else -1
                steps = [
                    direction * (float(b["x"]) - float(a["x"]))
                    for a, b in zip(samples, samples[1:])
                ]
                result["frozen_frames"] = sum(abs(step) < 0.001 for step in steps)
                result["min_forward_step"] = min(steps)
                assert min(steps) >= -0.01 and result["frozen_frames"] == 0, result
            report.append(result)
    return report


def measure(path, water_only=False):
    rows = list(csv.DictReader(path.open()))
    report = {}
    for phase, first, last in (
        ("bag_held", 420, 735),
        ("bag_no_eid_render", 780, 1035),
        ("water1", 1590, 2085),
        ("water2", 2460, 3045),
    ):
        if water_only and phase.startswith("bag"):
            continue
        samples = [r for r in rows if r["phase"] == phase and first <= int(r["tick"]) < last]
        assert len(samples) > 200, f"Missing scene: {phase}"
        intervals = sorted(float(r["interval_ms"]) for r in samples)
        result = {
            "samples": len(samples),
            "mean_interval_ms": statistics.mean(intervals),
            "p95_interval_ms": intervals[int(len(intervals) * 0.95)],
            "max_other_entities": max(int(r["other_entities"]) for r in samples),
            "max_local_spray": max(int(r["local_spray"]) for r in samples),
        }
        if phase.startswith("bag"):
            moving = [
                (a, b)
                for a, b in zip(samples, samples[1:])
                if 5 <= int(b["tick"]) % 72 < 17 or 41 <= int(b["tick"]) % 72 < 53
            ]
            assert moving and all(b["animation"].startswith("PickupWalk") for _, b in moving)
            result["frozen_moving_fraction"] = sum(
                abs(float(b["x"]) - float(a["x"])) < 0.001 for a, b in moving
            ) / len(moving)
            assert result["frozen_moving_fraction"] < 0.1, result
        else:
            assert all(float(r["current_y"]) != 0 for r in samples), "Missing native current"
            assert result["max_local_spray"] > 10, "Current spray disappeared"
            # Other entities include ordinary rain, ripples and room decoration.
            # Inspect the actual current spray's replica identity instead.
            result["max_replicated_spray"] = max(int(r["replicated_spray"]) for r in samples)
            assert result["max_replicated_spray"] == 0, "Current spray was replicated"
        report[phase] = result
    return report
