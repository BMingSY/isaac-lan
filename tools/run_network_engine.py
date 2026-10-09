#!/usr/bin/env python3
"""Own and close two isolated game processes; never touches a live installation."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time


def windows(path):
    return subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()


def execute(*args, timeout=30):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    text = result.stdout.decode("utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(text)
    return text


def log_path(lab):
    return lab / "profile/Documents/My Games/Binding of Isaac Repentance+/log.txt"


def read_log(lab):
    path = log_path(lab)
    return path.read_text(errors="replace") if path.exists() else ""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--extra-client", type=Path, action="append", default=[])
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--script", type=Path, required=True, help="State-sync Lua scenario")
    parser.add_argument(
        "--virtual-input",
        action="store_true",
        help="Enumerate virtual pads during isolated engine startup",
    )
    parser.add_argument(
        "--frontend",
        action="store_true",
        help="Use embedded native bridge with every Workshop mod disabled",
    )
    parser.add_argument(
        "--menu-start",
        action="store_true",
        help="Start the network game directly from the title/save menus",
    )
    parser.add_argument(
        "--progress-fixture",
        action="store_true",
        help="Give only the owned lab processes deliberately different unlock/counter states",
    )
    parser.add_argument(
        "--solo-fixture",
        action="store_true",
        help="Verify native solo save bytes before and after a LAN session in each owned lab",
    )
    parser.add_argument(
        "--automatic",
        action="store_true",
        help="Use the automatically loaded DLL instead of remote-thread injection",
    )
    parser.add_argument(
        "--installed",
        action="store_true",
        help="Install/uninstall the frozen package in the marked lab; retain profile isolation",
    )
    parser.add_argument("--completion", required=True, help="Required per-peer completion evidence")
    parser.add_argument(
        "--scenario-timeout",
        type=int,
        default=100,
        help="Seconds allowed after startup; continuous suites may run longer",
    )
    parser.add_argument(
        "--capture-ui",
        action="store_true",
        help="Capture embedded menu and game view in the owned lab",
    )
    parser.add_argument(
        "--check-local-stats",
        action="store_true",
        help="Read the native StatHUD caches and require only the local controller",
    )
    parser.add_argument(
        "--watch-floor-hud",
        action="store_true",
        help="Observe native HUD ownership throughout the floor animation after VISUAL_READY",
    )
    parser.add_argument(
        "--record-view",
        type=int,
        choices=range(4),
        help="Record an owned peer's pixels after the scenario emits VISUAL_READY",
    )
    parser.add_argument(
        "--native-record-view",
        type=int,
        choices=range(4),
        help="Archive native back-buffer frames for one owned peer throughout the run",
    )
    parser.add_argument(
        "--native-record-both",
        action="store_true",
        help="Archive both owned host/client views throughout the run",
    )
    parser.add_argument(
        "--frame-ms",
        type=int,
        default=16,
        help="Native recording sample interval, 16..1000 ms; background writer may drop frames",
    )
    parser.add_argument(
        "--exercise-menu",
        action="store_true",
        help="Use original Online entry, native chat typing, lobby ready and start controls",
    )
    parser.add_argument(
        "--menu-port",
        type=int,
        default=29506,
        help="TCP port entered through the native menu; non-default values also exercise validation",
    )
    parser.add_argument(
        "--latency-ms",
        type=int,
        default=0,
        help="Added one-way loopback delay; scenario reads lan-test-menu-port.txt",
    )
    parser.add_argument(
        "--exercise-official",
        action="store_true",
        help="Enter the original Online flow, return, then exercise LAN",
    )
    parser.add_argument(
        "--exercise-input",
        action="store_true",
        help="Send physical move/fire input only to the owned client window",
    )
    parser.add_argument(
        "--mod",
        type=Path,
        action="append",
        default=[],
        help="Copy an existing mod into a marked, isolated compatibility fixture",
    )
    parser.add_argument(
        "--client-mod",
        type=Path,
        action="append",
        default=[],
        help="Enable an additional fixture only on clients to verify advisory-only Mod differences",
    )
    parser.add_argument(
        "--host-mod",
        type=Path,
        action="append",
        default=[],
        help="Enable an additional fixture only on the host",
    )
    args = parser.parse_args()
    if not 10 <= args.scenario_timeout <= 1800:
        parser.error("Scenario timeout must be between 10 and 1800 seconds")
    if args.installed and not args.frontend:
        parser.error("--installed requires --frontend")
    if not 16 <= args.frame_ms <= 1000:
        parser.error("frame-ms must be 16..1000")
    if args.exercise_official and not args.exercise_menu:
        parser.error("--exercise-official requires --exercise-menu")
    if not 1 <= args.menu_port <= 65535:
        parser.error("--menu-port must be between 1 and 65535")
    if args.latency_ms and (
        not 0 < args.latency_ms <= 1000 or args.menu_port == 65535 or args.exercise_menu
    ):
        parser.error(
            "Latency fixture requires a scripted menu, delay 1..1000 and an available following port"
        )
    labs = [args.host.resolve(), args.client.resolve(), *(p.resolve() for p in args.extra_client)]
    roles = ["host", "client", "client2", "client3"][: len(labs)]
    if (
        len(labs) > 4
        or len(set(labs)) != len(labs)
        or any(not (lab / ".isaac-lan-lab").is_file() for lab in labs)
    ):
        raise SystemExit("Two to four distinct marked lab directories are required")
    live = json.loads(
        execute(
            "powershell.exe",
            "-NoProfile",
            "-Command",
            "ConvertTo-Json -Compress -InputObject @(Get-Process -Name isaac-ng -ErrorAction SilentlyContinue | Select-Object Id,Path)",
        )
    )
    targets = {windows(lab / "game/isaac-ng.exe").casefold() for lab in labs}
    if any((process.get("Path") or "").casefold() in targets for process in live):
        raise SystemExit("An owned lab is still running; close it before reusing its files")
    if args.native_record_view is not None and args.native_record_view >= len(labs):
        parser.error("Requested recording peer does not exist")
    source = Path(__file__).resolve().parent.parent
    script = args.script
    window = labs[0].parent / "lab_window.ps1"
    processes = []
    result = {
        "pass": False,
        "runs": [],
        "dll_sha256": hashlib.sha256((args.build / "isaac_lan_probe.dll").read_bytes()).hexdigest(),
        "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
    }
    if args.exercise_menu:
        result["menu_port"] = args.menu_port
    args.output.mkdir(parents=True, exist_ok=False)
    # Freeze both inputs before launching either peer. A build/edit performed
    # while this test runs must not silently change the second peer's version.
    tested_dll = args.output / "tested-probe.dll"
    tested_script = args.output / "test-harness.lua"
    shutil.copy2(args.build / "isaac_lan_probe.dll", tested_dll)
    shutil.copy2(script, tested_script)
    if args.automatic or args.installed:
        shutil.copy2(args.build / "winmm.dll", args.output / "tested-loader.dll")
        result["loader_sha256"] = hashlib.sha256(
            (args.output / "tested-loader.dll").read_bytes()
        ).hexdigest()
    installed_labs = []
    package = args.output / "installed-package"
    if args.installed:
        package.mkdir()
        shutil.copy2(tested_dll, package / "isaac_lan_probe.dll")
        shutil.copy2(args.output / "tested-loader.dll", package / "winmm.dll")
        shutil.copy2(source / "package/install.ps1", package)
        shutil.copy2(args.build / "isaac_lan_check.exe", package)
        result["checker_sha256"] = hashlib.sha256(
            (package / "isaac_lan_check.exe").read_bytes()
        ).hexdigest()
        payload = {
            "format": 1,
            "game_build": "1.9.7.17.J460",
            "files": {
                "isaac_lan_probe.dll": result["dll_sha256"],
                "winmm.dll": result["loader_sha256"],
                "isaac_lan_check.exe": result["checker_sha256"],
            },
        }
        (package / "payload.json").write_text(json.dumps(payload))
        result["installed_branch"] = True
        result["automatic_loading"] = args.automatic or args.installed
    fixtures = []
    fixture_roles = {}
    for mod, enabled_roles in (
        [(mod, roles) for mod in args.mod]
        + [(mod, roles[1:]) for mod in args.client_mod]
        + [(mod, roles[:1]) for mod in args.host_mod]
    ):
        name = "lan_compat_" + mod.name
        frozen = args.output / "mods" / name
        shutil.copytree(mod, frozen)
        (frozen / "disable.it").unlink(missing_ok=True)
        (frozen / ".lan-compat-fixture").write_text("Owned isolated LAN compatibility fixture.\n")
        fixtures.append(frozen)
        fixture_roles[name] = enabled_roles
    result["mods"] = {
        fixture.name: {
            str(p.relative_to(fixture)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(fixture.rglob("*"))
            if p.is_file()
        }
        for fixture in fixtures
    }
    result["mod_roles"] = fixture_roles
    result["different_client_mods"] = bool(args.client_mod or args.host_mod)
    shutil.copy2(source / "tools/lab_window.ps1", window)
    started = time.monotonic()

    def control(pid, action, value=""):
        return execute(
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            windows(window),
            "-GameProcessId",
            str(pid),
            "-Action",
            action,
            "-ImagePath" if action == "Capture" else "-Value",
            value,
        )

    def menu_control(pid, key):
        lab = labs[processes.index(pid)]
        path = lab / "game/lan-test-pad.txt"
        buttons = {
            "{ENTER}": 4096,
            "{ESC}": 8192,
            "{UP}": 1,
            "{DOWN}": 2,
            "{LEFT}": 4,
            "{RIGHT}": 8,
        }
        staged = path.with_suffix(".tmp")
        staged.write_text(str(buttons[key]))
        staged.replace(path)
        deadline = time.monotonic() + 10
        while path.exists():
            if time.monotonic() > deadline:
                raise RuntimeError("Lab virtual gamepad command was not consumed")
            time.sleep(0.05)

    def installation(lab, mode):
        return execute(
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            windows(package.resolve() / "install.ps1"),
            "-Mode",
            mode,
            "-GameDirectory",
            windows(lab / "game"),
        )

    def menu_state(pid):
        return json.loads(
            execute(
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                windows(source / "tools/lab_menu_state.ps1"),
                "-GameProcessId",
                str(pid),
            )
        )

    relay = None
    floor_hud = None

    def interrupted(signum, _frame):
        raise RuntimeError(f"Test interrupted by signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        if args.latency_ms:
            from delayed_relay import DelayedRelay

            relay = DelayedRelay(args.menu_port + 1, args.menu_port, args.latency_ms)
            result["one_way_latency_ms"] = args.latency_ms
        for lab, role in zip(labs, roles):
            # Windows refuses replacement if an older process still has the DLL
            # loaded; fail before removing any saved internal test run.
            shutil.copy2(tested_dll, lab / "game/isaac_lan_probe.dll")
            loader, marker = lab / "game/winmm.dll", lab / "game/.isaac-lan-loader"
            if loader.exists() and not marker.is_file():
                raise RuntimeError("Refusing to replace an unowned multimedia DLL")
            if args.automatic or args.installed:
                shutil.copy2(args.output / "tested-loader.dll", loader)
                marker.write_text("Owned isolated LAN automatic loader.\n")
            elif marker.is_file():
                loader.unlink(missing_ok=True)
                marker.unlink()
            if args.installed:
                # These are the just-copied, hash-frozen lab inputs. Exercise
                # the real installer on an empty extension destination.
                loader.unlink()
                (lab / "game/isaac_lan_probe.dll").unlink()
                print(installation(lab, "Install"), flush=True)
                installed_labs.append(lab)
            if args.virtual_input:
                (lab / "virtual-input.test").write_text("Internal input test only.\n")
            else:
                (lab / "virtual-input.test").unlink(missing_ok=True)
            (lab / "visual-capture.test").unlink(missing_ok=True)
            if args.native_record_both or args.native_record_view == roles.index(role):
                if (lab / "visual-frames").exists():
                    shutil.rmtree(lab / "visual-frames")
                (lab / "visual-capture.test").write_text(str(args.frame_ms) + "\n")
            internal = lab / "game/mods/lan_native_internal_probe"
            for old in (lab / "game/mods").glob("lan_compat_*"):
                if (old / ".lan-compat-fixture").is_file():
                    (old / "disable.it").touch()
            for fixture in fixtures:
                if role not in fixture_roles[fixture.name]:
                    continue
                destination = lab / "game/mods" / fixture.name
                if destination.exists():
                    if not (destination / ".lan-compat-fixture").is_file():
                        raise RuntimeError("Refusing to overwrite an unowned compatibility fixture")
                    shutil.rmtree(destination)
                shutil.copytree(fixture, destination)
            if args.frontend:
                (lab / "frontend.test").write_text("Internal frontend test only.\n")
                (internal / "disable.it").touch()
                shutil.copy2(tested_script, lab / "frontend-scenario.lua")
            else:
                (lab / "frontend.test").unlink(missing_ok=True)
                (lab / "frontend-scenario.lua").unlink(missing_ok=True)
                (internal / "disable.it").unlink(missing_ok=True)
                shutil.copy2(tested_script, internal / "main.lua")
            (log_path(lab).parent / "gamestate1.dat").unlink(missing_ok=True)
            log_path(lab).unlink(missing_ok=True)
            for file in (lab / "game").glob("lan-test-digest-*.txt"):
                file.unlink()
            (lab / "game/lan-test-pad.txt").unlink(missing_ok=True)
            (lab / "game/lan-test-role.txt").write_text(role + "\n")
            (lab / "game/lan-test-solo-fixture.txt").write_text(
                ("1" if args.solo_fixture else "0") + "\n"
            )
            (lab / "game/lan-test-player-count.txt").write_text(str(len(labs)) + "\n")
            (lab / "game/lan-test-menu-port.txt").write_text(
                str(args.menu_port + (1 if args.latency_ms and role != "host" else 0)) + "\n"
            )
            advisory = lab / "game/lan-test-mod-advisory.txt"
            if args.client_mod or args.host_mod:
                advisory.touch()
            else:
                advisory.unlink(missing_ok=True)
            hold = lab / "game/lan-test-hold-lobby"
            if args.progress_fixture:
                hold.touch()
            else:
                hold.unlink(missing_ok=True)
            shutil.copy2(args.build / "isaac_lan_lab.exe", lab / "isaac_lan_lab.exe")
            response = execute(
                str(lab / "isaac_lan_lab.exe"),
                windows(lab),
                *(["--automatic"] if args.automatic or args.installed else []),
            )
            match = re.search(r"(?:bootstrap_status=0|autoload_started=1) pid=(\d+)", response)
            if not match:
                raise RuntimeError(response)
            pid = int(match[1])
            processes.append(pid)
            result["runs"].append({"role": role, "pid": pid})
            print(f"Started isolated {role}: {pid}", flush=True)
            result["runs"][-1]["game_sha256"] = hashlib.sha256(
                (lab / "game/isaac-ng.exe").read_bytes()
            ).hexdigest()
            deadline = time.monotonic() + (120 if args.exercise_menu else 45)
            while "playing cutscene 1" not in read_log(lab):
                if time.monotonic() >= deadline:
                    raise RuntimeError(f"{role} did not reach intro")
                time.sleep(0.1)
            control(pid, "PostKeys", "{SPACE}")
            if args.menu_start:
                time.sleep(1)
                control(pid, "PostKeys", "{ENTER}")
                time.sleep(1)
                control(pid, "PostKeys", "{ENTER}")
                time.sleep(1)
                if args.progress_fixture:
                    fixture = [
                        "powershell.exe",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        windows(source / "tools/lab_progress.ps1"),
                        "-GameProcessId",
                        str(pid),
                    ]
                    if role == "host":
                        fixture.append("-HostFixture")
                    print(execute(*fixture), flush=True)
                    hold.unlink()
            if args.exercise_menu or (args.capture_ui and role == "host"):
                navigate = (
                    menu_control
                    if args.exercise_menu
                    else lambda pid, key: control(pid, "PostKeys", key)
                )
                navigate(pid, "{DOWN}")  # Continue is disabled in the empty lab profile.
                navigate(pid, "{ENTER}")
                if args.capture_ui:
                    control(pid, "Capture", windows(args.output.resolve() / (role + "-menu.png")))
                if args.exercise_menu:
                    if args.exercise_official and role == "host":
                        # Exercise leaving a LAN lobby before handing control
                        # back to the game's own Online branch.
                        menu_control(pid, "{DOWN}")
                        menu_control(pid, "{ENTER}")
                        menu_control(pid, "{ENTER}")  # create
                        menu_control(pid, "{UP}")
                        menu_control(pid, "{ENTER}")  # last row: leave
                        menu_control(pid, "{ESC}")
                        menu_control(pid, "{UP}")  # modes, official
                        menu_control(pid, "{ENTER}")  # Official is the first choice.
                        time.sleep(0.5)
                        snapshot = menu_state(pid)
                        result["official_entry_state"] = snapshot
                        control(
                            pid, "Capture", windows(args.output.resolve() / "official-online.png")
                        )
                        native = (lab / "probe.log").read_text().rsplit("bootstrap=PASS", 1)[-1]
                        assert "native_online_entry=OFFICIAL" in native
                        entry = native.split("native_online_entry=OFFICIAL", 1)[0]
                        assert (
                            entry.rfind("input_virtual=DISABLED")
                            > entry.rfind("input_virtual=ENABLED")
                            >= 0
                        )
                        assert snapshot["menu"] != 3 or snapshot["dialogs"] > 0, (
                            "Original Online did not open its own menu or dialog"
                        )
                        for _ in range(5):
                            if snapshot["menu"] == 3 and snapshot["dialogs"] == 0:
                                break
                            menu_control(pid, "{ESC}")
                            time.sleep(0.2)
                            snapshot = menu_state(pid)
                        assert snapshot["menu"] == 3 and snapshot["dialogs"] == 0, (
                            "Original Online did not return to the game menu"
                        )
                        menu_control(pid, "{ENTER}")  # Reopen the mode chooser.
                    menu_control(pid, "{DOWN}")  # LAN in the Online mode chooser.
                    menu_control(pid, "{ENTER}")
                    if role == "client":
                        menu_control(pid, "{DOWN}")
                        menu_control(pid, "{ENTER}")
                        for key in "127.0.0.2":
                            control(pid, "PostKeys", key)
                        control(pid, "PostKeys", "{BACKSPACE}")
                        control(pid, "PostKeys", "1")
                        if args.capture_ui:
                            control(pid, "Capture", windows(args.output.resolve() / "chat-ip.png"))
                        menu_control(pid, "{ENTER}")
                        menu_control(pid, "{DOWN}")
                    if args.menu_port != 29506:
                        if role == "host":
                            menu_control(pid, "{DOWN}")
                            menu_control(pid, "{DOWN}")
                        menu_control(pid, "{ENTER}")  # port
                        for _ in range(5):
                            control(pid, "PostKeys", "{BACKSPACE}")
                        for key in "65536":
                            control(pid, "PostKeys", key)
                        menu_control(pid, "{ENTER}")  # Invalid value must remain editable.
                        if args.capture_ui:
                            control(
                                pid,
                                "Capture",
                                windows(args.output.resolve() / (role + "-port-invalid.png")),
                            )
                        for _ in range(5):
                            control(pid, "PostKeys", "{BACKSPACE}")
                        for key in "A." + str(args.menu_port):
                            control(pid, "PostKeys", key)
                        if args.capture_ui:
                            control(
                                pid,
                                "Capture",
                                windows(args.output.resolve() / (role + "-port.png")),
                            )
                        menu_control(pid, "{ENTER}")
                        if role == "host":
                            menu_control(pid, "{UP}")
                            menu_control(pid, "{UP}")
                    if role == "client":
                        menu_control(pid, "{DOWN}")  # join, after port row
                    menu_control(pid, "{ENTER}")
                else:
                    control(pid, "PostKeys", "{ESC}")
            expected = "LAN_NETWORK MENU_READY" if args.menu_start else "LAN_NETWORK GAME_STARTED"
            while expected not in read_log(lab):
                errors = [
                    line
                    for line in read_log(lab).splitlines()
                    if "LAN_NETWORK FAILED" in line or "Error in" in line
                ]
                if errors:
                    raise RuntimeError(errors[-1])
                if time.monotonic() >= deadline:
                    raise RuntimeError(f"{role} did not start an isolated run")
                if not args.menu_start:
                    control(pid, "PostKeys", "{ENTER}")
                time.sleep(0.4)
            if args.exercise_menu:
                menu_control(pid, "{DOWN}")
                menu_control(pid, "{ENTER}")  # ready
        if args.exercise_menu:
            pid = processes[0]
            menu_control(pid, "{DOWN}")
            menu_control(pid, "{DOWN}")
            menu_control(pid, "{ENTER}")  # seed
            for key in "YV039KQF":
                control(pid, "PostKeys", key)
            menu_control(pid, "{ENTER}")
            menu_control(pid, "{DOWN}")
            if args.capture_ui:
                control(pid, "Capture", windows(args.output.resolve() / "lobby.png"))
            menu_control(pid, "{ENTER}")  # start through UI
        deadline = time.monotonic() + args.scenario_timeout
        exercised = False
        recorded = False
        solo_saved, solo_continued, solo_hashes = set(), set(), {}
        while time.monotonic() < deadline:
            if relay and relay.error:
                raise RuntimeError("Latency relay: " + relay.error)
            logs = [read_log(lab) for lab in labs]
            if args.solo_fixture:
                for lab, role, pid, log in zip(labs, roles, processes, logs):
                    saved_file = log_path(lab).parent / "gamestate1.dat"

                    def solo_action(action):
                        print(
                            execute(
                                "powershell.exe",
                                "-NoProfile",
                                "-ExecutionPolicy",
                                "Bypass",
                                "-File",
                                windows(source / "tools/lab_solo.ps1"),
                                "-GameProcessId",
                                str(pid),
                                "-Action",
                                action,
                            ),
                            flush=True,
                        )

                    if role not in solo_saved and "LAN_NETWORK SOLO_READY" in log:
                        solo_action("SaveExit")
                        solo_saved.add(role)
                    if (
                        role not in solo_hashes
                        and "LAN_NETWORK SOLO_FILE_READY" in log
                        and saved_file.exists()
                        and saved_file.stat().st_size > 0
                    ):
                        solo_hashes[role] = hashlib.sha256(saved_file.read_bytes()).hexdigest()
                        shutil.copy2(saved_file, args.output / f"{role}-solo-before.dat")
                    if role not in solo_continued and "LAN_NETWORK SOLO_NETWORK_EXIT" in log:
                        assert role in solo_hashes and saved_file.is_file(), (
                            "LAN erased an existing native solo save"
                        )
                        shutil.copy2(saved_file, args.output / f"{role}-solo-after.dat")
                        assert (
                            hashlib.sha256(saved_file.read_bytes()).hexdigest() == solo_hashes[role]
                        ), "LAN overwrote an existing native solo save"
                        result.setdefault("preserved_solo_sha256", {})[role] = solo_hashes[role]
                        solo_action("Continue")
                        solo_continued.add(role)
            if (
                args.exercise_input
                and not exercised
                and all("ISAAC_LAN READY" in log for log in logs)
            ):
                control(processes[-1], "Keys", "D")
                control(processes[-1], "Keys", "{RIGHT}")
                exercised = True
            errors = [
                line
                for log in logs
                for line in log.splitlines()
                if "LAN_NETWORK FAILED" in line or "Error in" in line or "Caught exception" in line
            ]
            for lab in labs:
                native = (
                    (lab / "probe.log").read_text(errors="replace").rsplit("bootstrap=PASS", 1)[-1]
                )
                errors.extend(
                    line
                    for line in native.splitlines()
                    if "frontend_error=" in line
                    or "native_exception" in line
                    or "integration_error=_IsaacLanRoomEntered" in line
                )
            if errors:
                raise RuntimeError("\n".join(errors))
            if (
                args.watch_floor_hud
                and floor_hud is None
                and all("LAN_NETWORK VISUAL_READY" in log for log in logs)
            ):
                from check_floor_hud import FloorHudWatch

                floor_hud = FloorHudWatch(processes, roles, args.output)
            if (
                args.record_view is not None
                and not recorded
                and all("LAN_NETWORK VISUAL_READY" in log for log in logs)
            ):
                if args.record_view >= len(processes):
                    raise RuntimeError("Requested visual peer does not exist")
                execute(
                    "powershell.exe",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    windows(source / "tools/lab_visual_series.ps1"),
                    "-GameProcessId",
                    str(processes[args.record_view]),
                    "-OutputDirectory",
                    windows(args.output.resolve() / "visual-series"),
                    "-Seconds",
                    "6",
                    "-BackgroundCapture",
                    timeout=16,
                )
                recorded = True
            if all(args.completion in log for log in logs):
                if args.watch_floor_hud:
                    assert floor_hud is not None, "Floor HUD observation never started"
                    result["floor_hud"] = floor_hud.finish()
                result["pass"] = True
                if args.check_local_stats:
                    for slot, (role, pid) in enumerate(zip(roles, processes)):
                        hud = json.loads(
                            execute(
                                "powershell.exe",
                                "-NoProfile",
                                "-ExecutionPolicy",
                                "Bypass",
                                "-File",
                                windows(source / "tools/lab_hud_state.ps1"),
                                "-GameProcessId",
                                str(pid),
                            )
                        )
                        result.setdefault("local_stats", {})[role] = hud
                        assert hud["primary_controller"] == slot + 1, (
                            f"{role}: main pocket/HUD bound to another player"
                        )
                        assert hud["entries"] and all(
                            p["controller"] == slot + 1 for p in hud["entries"]
                        ), f"{role}: teammate in native StatHUD"
                        assert hud["entries"][0]["column"] == 0, (
                            f"{role}: local stats were left in a teammate column"
                        )
                        assert {p["controller"] for p in hud["players"]} == set(
                            range(1, len(roles) + 1)
                        ), f"{role}: original multiplayer player HUD omitted a participant"
                        assert all(
                            p["hearts"] > 0 for p in hud["players"] if p["max_hearts"] > 0
                        ), f"{role}: local red heart HUD disappeared"
                        assert all(p["controller"] == slot + 1 for p in hud["history"]), (
                            f"{role}: teammate in item history"
                        )
                if args.capture_ui:
                    control(
                        processes[0], "Capture", windows(args.output.resolve() / "host-game.png")
                    )
                    control(processes[-1], "Capture", windows(args.output.resolve() / "game.png"))
                break
            time.sleep(0.25)
        if not result["pass"]:
            raise RuntimeError("Two-process engine synchronization test timed out")
    except Exception as error:
        result["pass"] = False
        result["error"] = str(error)
    finally:
        if floor_hud is not None:
            floor_hud.stop()
        # Only PIDs returned by our own isolated child runner are controlled.
        closed = set()
        for pid in processes:
            try:
                control(pid, "Close")
                closed.add(pid)
            except Exception as error:
                result.setdefault("close_errors", []).append(str(error))
        if relay:
            relay.close()
        for lab, role in zip(labs, roles):
            out = args.output / role
            out.mkdir()
            if (
                (args.native_record_both or args.native_record_view == roles.index(role))
                and len(processes) > roles.index(role)
                and processes[roles.index(role)] in closed
            ):
                (lab / "visual-capture.test").unlink(missing_ok=True)
                try:
                    if (lab / "visual-frames").exists():
                        shutil.move(str(lab / "visual-frames"), out / "frames")
                except Exception as error:
                    result.setdefault("close_errors", []).append(
                        f"{role} recording cleanup: {error}"
                    )
            for path in [log_path(lab), lab / "probe.log"]:
                if path.exists():
                    shutil.copy2(path, out / path.name)
            for suffix in ("txt", "csv"):
                for path in (lab / "game").glob("lan-test-digest-*." + suffix):
                    shutil.copy2(path, out / path.name)
        for lab in installed_labs:
            try:
                print(installation(lab, "Uninstall"), flush=True)
            except Exception as error:
                result.setdefault("close_errors", []).append(str(error))
        for lab in labs:
            for fixture in fixtures:
                destination = lab / "game/mods" / fixture.name
                if (destination / ".lan-compat-fixture").is_file():
                    (destination / "disable.it").touch()
            (lab / "game/lan-test-mod-advisory.txt").unlink(missing_ok=True)
        result["seconds"] = time.monotonic() - started
        (args.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["pass"] and not result.get("close_errors") else 1)


if __name__ == "__main__":
    main()
