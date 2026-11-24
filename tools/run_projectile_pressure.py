#!/usr/bin/env python3
"""Compare complete projectile synchronization with one protected native pair."""

import argparse
from bisect import bisect_right
import json
from math import ceil
import re
from pathlib import Path
import subprocess

from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup
from testing.engine import configure_interrupts, engine_command, run_engine
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]


def combat_views(log):
    views = {}
    for series in re.findall(r"LAN_COMBAT_POSITIONS ([0-9.,;-]+)", log):
        for record in series.split(";"):
            tick, milliseconds, *positions = record.split(",")
            views[int(tick)] = (int(milliseconds), positions)
    return views


def compare_combat(host_log, client_log):
    host, guest = combat_views(host_log), combat_views(client_log)
    different = [
        tick
        for tick, (_, positions) in guest.items()
        if tick not in host or host[tick][1] != positions
    ]
    report = {"guest_views": len(guest), "different_ticks": different}
    if different or not guest:
        return report
    # Both protected game processes use the same Windows monotonic clock.
    arrivals = sorted((at, host[tick][0]) for tick, (at, _) in guest.items())
    times = [at for at, _ in arrivals]
    windows = re.findall(r"LAN_COMBAT_WINDOW ([\w-]+) (\d+)", host_log)

    def measurement(limits):
        if len(limits) != 2:
            return {}
        start, end = limits
        if end <= start or times[0] > start:
            return {}
        current = [at for at in times if start <= at < end]
        if not current:
            return {}
        gaps = [b - a for a, b in zip([start] + current, current + [end])]
        ages = sorted(t - arrivals[bisect_right(times, t) - 1][1] for t in range(start, end, 10))
        return dict(
            applied_hz=round(len(current) * 1000 / (end - start), 2),
            newest_state_age_p95_ms=ages[ceil(len(ages) * 0.95) - 1],
            max_update_gap_ms=max(gaps),
        )

    for case in dict.fromkeys(name for name, _ in windows):
        values = measurement([int(at) for name, at in windows if name == case])
        if case == "moving-enemy-fire":
            report.update(values)
        else:
            report.setdefault("cases", {})[case] = values
    return report


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=35640)
    parser.add_argument("--latency-ms", type=int, default=40)
    parser.add_argument(
        "--phase-profile", action="store_true", help="Enable detailed per-entity timing"
    )
    parser.add_argument(
        "--verify", action="store_true", help="Also check links, room and floor cleanup"
    )
    cases = parser.add_mutually_exclusive_group()
    cases.add_argument(
        "--late-game",
        action="store_true",
        help="Compare actual fetus/Tech 0 fire, multishot and a mixed barrage on both peers",
    )
    cases.add_argument(
        "--combat",
        action="store_true",
        help="Compare a moving shooter and hostile shot at each applied tick under laser load",
    )
    parser.add_argument(
        "--downstream-kbps",
        type=int,
        default=0,
        help="Limit the isolated relay downstream, in decimal kilobits per second",
    )
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65534 or not 0 <= args.latency_ms <= 500:
        parser.error("Require port 1024..65534 and one-way latency 0..500 ms")
    if args.downstream_kbps < 0 or (args.downstream_kbps and not args.latency_ms):
        parser.error("A downstream cap requires a nonnegative rate and an active latency relay")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs, exclusive=not args.verify)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output)
    report = {"passed": False, "protected": protected.report(), "verification": args.verify}
    try:
        script = output / "fixture.lua"
        script.write_text(
            f"_IsaacLanProjectileFixture = {{ verify = {str(args.verify).lower()}, combat = {str(args.combat).lower()} }}\n"
            + (
                "_IsaacLanProjectileFixture.lateGame = (function()\n"
                + (ROOT / "tests/support/late_game_combat.lua").read_text()
                + "\nend)()\n"
                if args.late_game
                else ""
            )
            + (ROOT / "tests/state_projectile_pressure.lua").read_text()
        )
        command = engine_command(
            labs,
            args.build,
            output / "engine",
            script,
            "LAN_NETWORK PASS projectile pressure",
            "--frontend",
            "--no-luadebug",
            "--menu-start",
            "--virtual-input",
            "--automatic",
            "--menu-port",
            str(args.port),
            "--latency-ms",
            str(args.latency_ms),
            "--scenario-timeout",
            "300",
        )
        if args.downstream_kbps:
            config = output / "relay-control.json"
            config.write_text(
                json.dumps(
                    {
                        "delay_ms": args.latency_ms,
                        "downstream_bytes_per_second": args.downstream_kbps * 125,
                    }
                )
            )
            command.extend(("--relay-control", str(config)))
        if args.phase_profile:
            command.append("--performance")
        if args.heap_check:
            command.append("--heap-check")
        report["command"] = command
        with (output / "engine.log").open("w") as log:
            result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        report["returncode"] = result.returncode
        result_path = output / "engine/result.json"
        if result_path.is_file():
            report["result"] = json.loads(result_path.read_text())
        report["passed"] = result.returncode == 0 and report.get("result", {}).get("pass") is True
        report["measurements"] = {}
        observed = {}
        for role in ("host", "client"):
            path = output / "engine" / role / "log.txt"
            if path.is_file():
                log = path.read_text(errors="replace")
                if args.combat or args.late_game:
                    observed[role] = log
                report["measurements"][role] = [
                    json.loads(line.split("LAN_PROJECTILE_PRESSURE ", 1)[1])
                    for line in log.splitlines()
                    if "LAN_PROJECTILE_PRESSURE {" in line
                ]
        if args.combat or args.late_game:
            combat = compare_combat(observed.get("host", ""), observed.get("client", ""))
            report["combat"] = combat
            report["passed"] = (
                report["passed"] and bool(combat["guest_views"]) and not combat["different_ticks"]
            )
            if args.late_game:
                windows = combat.get("cases", {})
                report["passed"] = report["passed"] and len(windows) == 3 and all(windows.values())
        idle(labs, exclusive=not args.verify)
    finally:
        finish_run(protected, report, output)
    print(json.dumps({"passed": report["passed"], "restored": report["restored"]}))
    return 0 if report["passed"] and report["restored"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
