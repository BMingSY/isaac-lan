#!/usr/bin/env python3
"""Run selected character, route, Greed and LANBOT fixtures with one protected native pair."""

import argparse
from testing.special_routes import lanbot_behavior_passed, lanbot_greed_result
import json
from pathlib import Path
import re
import subprocess
from testing.special_routes import CASES, DIAGNOSTICS, build
from testing.results import finish_run
from testing.engine import configure_interrupts, engine_command, run_engine
from lab_profile import validate_labs as validate_owned_labs
from lab_profile import ProtectedLabs, idle
from game_logs import log_path

ROOT = Path(__file__).resolve().parents[1]


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--injected",
        action="store_true",
        help="Use the isolated injection backend; skip autoload validation",
    )
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mod", type=Path, action="append", default=[])
    parser.add_argument("--case", choices=CASES + DIAGNOSTICS, action="append")
    parser.add_argument(
        "--first-floor",
        action="store_true",
        help="Start the Lamb ending on the first floor within the six-route suite",
    )
    parser.add_argument("--port", type=int, default=30220)
    parser.add_argument("--latency-ms", type=int, default=75)
    parser.add_argument(
        "--record-relay",
        action="store_true",
        help="Archive the delayed relay stream for offline replay",
    )
    parser.add_argument(
        "--heap-check",
        action="store_true",
        help="Observe owned games and preserve full crash dumps",
    )
    parser.add_argument(
        "--performance",
        action="store_true",
        help="Enable metrics only in the restored lab configuration",
    )
    parser.add_argument(
        "--record",
        action="store_true",
        help="Opt in to native frame archives for visual regressions",
    )
    parser.add_argument("--record-client", action="store_true", help="Record only the guest view")
    parser.add_argument(
        "--frame-ms", type=int, default=250, help="Recording interval (16..1000 ms)"
    )
    args = parser.parse_args()
    cases = args.case or CASES
    if not 0 <= args.latency_ms <= 5000:
        parser.error("Latency must be between 0 and 5000 ms")
    if args.record_relay and not args.latency_ms:
        parser.error("Relay recording requires positive latency")
    if not 16 <= args.frame_ms <= 1000 or args.record and args.record_client:
        parser.error("Choose one recording mode and a frame interval of 16..1000 ms")
    if len(set(cases)) != len(cases):
        parser.error("Each case must appear once")
    if "endings" in cases and cases[-1] != "endings":
        parser.error("The six-route ending diagnostic must run last")
    if args.first_floor and "endings" not in cases:
        parser.error("First-floor coverage requires --case endings")
    if "campaign" in cases and cases[-1] != "campaign":
        parser.error("The first-floor campaign must run last")
    if "lanbot-campaign" in cases and cases[-1] != "lanbot-campaign":
        parser.error("The LANBOT first-floor campaign must run last")
    if "lanbot-greed" in cases and cases[-1] != "lanbot-greed":
        parser.error("The LANBOT Greed challenge must run last")
    labs = validate_owned_labs(
        [args.host.resolve(), args.client.resolve()], args.output.resolve(), count=None
    )
    idle(labs)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    script = output / "suite.lua"
    build(script, cases, first_floor=args.first_floor)
    protected = ProtectedLabs(labs, output, roles=("host", "client"))
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        script,
        "LAN_NETWORK PASS all selected character and side routes",
        "--frontend",
        "--menu-start",
        "--virtual-input",
        "--no-luadebug",
        "--progress-fixture",
        "--alt-path-fixture",
        "--hush-fixture",
        "--latency-ms",
        str(args.latency_ms),
        "--menu-port",
        str(args.port),
        "--scenario-timeout",
        "3600"
        if any(
            name in cases
            for name in (
                "endings",
                "ascent-compat",
                "campaign",
                "greed",
                "greedier",
                "lanbot-campaign",
                "lanbot-greed",
            )
        )
        else "900",
    )
    if not args.injected:
        command.append("--automatic")
    if args.record_relay:
        command.append("--record-relay")
    if "ascent-compat" in cases:
        command.append("--ascent-fixture")
    if "lazarus" in cases:
        command.append("--lazarus-fixture")
    if any(
        name in cases
        for name in (
            "endings",
            "floor-sources",
            "campaign",
            "victory-lap",
            "victory-no",
            "greed",
            "greedier",
            "lanbot-campaign",
            "lanbot-greed",
        )
    ):
        command.append("--endings-fixture")
    for option in ("heap-check", "performance"):
        if getattr(args, option.replace("-", "_")):
            command.append("--" + option)
    if args.record:
        command += ["--native-record-both", "--frame-ms", str(args.frame_ms)]
    elif args.record_client:
        command += ["--native-record-view", "1", "--frame-ms", str(args.frame_ms)]
    for mod in args.mod:
        command += ["--mod", str(mod.resolve())]
    report = {"passed": False, "restored": False, "cases": {}, "command": command}
    try:
        if any(
            name in cases
            for name in (
                "ascent-compat",
                "dogma-warning",
                "campaign",
                "victory-lap",
                "victory-no",
                "greed",
                "greedier",
                "lanbot-campaign",
                "lanbot-greed",
            )
        ):
            # Prerequisite unlocks can queue native achievement screens and
            # pause world updates. This owned profile is restored in finally.
            for lab in labs:
                options = log_path(lab).parent / "options.ini"
                text = options.read_text()
                if re.search(r"(?m)^PopUps=", text):
                    text = re.sub(r"(?m)^PopUps=.*$", "PopUps=0", text)
                else:
                    text += "\nPopUps=0\n"
                options.write_text(text)
            report["native_options"] = {"PopUps": 0}
        with (output / "engine.log").open("w") as log:
            result = run_engine(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        for index, name in enumerate(cases, 1):
            report["cases"][name] = {}
            for role in ("host", "client"):
                path = output / "engine" / role / "log.txt"
                text = path.read_text(errors="replace") if path.exists() else ""
                report["cases"][name][role] = {
                    "passed": "SPECIAL_CASE_PASS index=" + str(index) in text,
                    "checkpoints": [
                        line
                        for line in text.splitlines()
                        if (
                            "SIDE " + name + " " in line
                            or name
                            in (
                                "home",
                                "home-debug",
                                "endings",
                                "dogma-warning",
                                "ascent-compat",
                                "campaign",
                                "victory-lap",
                                "victory-no",
                            )
                            and "ENDINGS " in line
                            or name == "lanbot"
                            and "LANBOT_CASE " in line
                            or name == "lanbot-campaign"
                            and "LANBOT_CAMPAIGN " in line
                            or name == "lanbot-spiders"
                            and "LANBOT_SPIDERS " in line
                            or name == "lanbot-greed"
                            and "LANBOT_GREED " in line
                            or name == "shared-curses"
                            and "SHARED_CURSES " in line
                            or name == "shared-deals"
                            and "SHARED_DEALS " in line
                            or name == "party-compat"
                            and "PARTY_COMPAT " in line
                            or name == "death-certificate"
                            and "DEATH_CERTIFICATE " in line
                            or name == "item-generation"
                            and "ITEM_GENERATION " in line
                            or name == "deep-pockets"
                            and "DEEP_POCKETS " in line
                            or name in ("greed", "greedier")
                            and ("GREED mode=" + ("3" if name == "greedier" else "2") + " ") in line
                            or name in ("audio", "motion", "floor-items", "mod-integrations")
                            and "LAN_NETWORK " in line
                            and "SIDE " not in line
                            or name == "lazarus"
                            and "LAN_NETWORK " in line
                            and "SIDE " not in line
                            or name == "rewind"
                            and "LAN_NETWORK " in line
                            and "SIDE " not in line
                        )
                    ],
                }
        report["passed"] = result.returncode == 0 and all(
            peer["passed"] for case in report["cases"].values() for peer in case.values()
        )
        if "victory-lap" in cases:
            lap = report["cases"]["victory-lap"]
            report["victory_lap_passed"] = all(
                any(
                    "VICTORY_LAP_PASS host_decision=true lap=1" in line
                    for line in peer["checkpoints"]
                )
                for peer in lap.values()
            ) and any(
                "VICTORY_LAP_GUEST_INPUT_IGNORED" in line for line in lap["host"]["checkpoints"]
            )
            report["passed"] = report["passed"] and report["victory_lap_passed"]
        if "victory-no" in cases:
            report["victory_no_passed"] = all(
                any(
                    "VICTORY_NO_PASS host_decision=true lap=0 native_win=true" in line
                    for line in peer["checkpoints"]
                )
                for peer in report["cases"]["victory-no"].values()
            )
            report["passed"] = report["passed"] and report["victory_no_passed"]
        if "lanbot" in cases:
            report["lanbot_behavior_passed"] = lanbot_behavior_passed(
                report["cases"]["lanbot"]["host"]["checkpoints"]
            )
            report["passed"] = report["passed"] and report["lanbot_behavior_passed"]
        if "lanbot-greed" in cases:
            try:
                report["lanbot_greed"] = lanbot_greed_result(
                    report["cases"]["lanbot-greed"]["host"]["checkpoints"]
                )
                report["passed"] = (
                    report["passed"] and report["lanbot_greed"]["outcome"] != "bot_error"
                )
            except (ValueError, KeyError) as error:
                report["passed"] = False
                report["lanbot_greed_error"] = str(error)
        if all(
            name
            in ("greed", "greedier", "lanbot", "lanbot-campaign", "lanbot-spiders", "lanbot-greed")
            for name in cases
        ):
            report["native_game_starts"] = {}
            for role in ("host", "client"):
                probe = output / "engine" / role / "probe.log"
                text = probe.read_text(errors="replace") if probe.exists() else ""
                starts = text.rsplit("bootstrap=PASS", 1)[-1].count(
                    "network_engine_start=REQUESTED"
                )
                report["native_game_starts"][role] = starts
                report["passed"] = report["passed"] and starts == len(cases)
    finally:
        finish_run(protected, report, output)
    print(
        json.dumps(
            {
                "passed": report["passed"],
                "restored": report["restored"],
                "report": str(output / "report.json"),
            },
            indent=2,
        )
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
