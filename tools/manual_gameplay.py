#!/usr/bin/env python3
"""Repeat normal menu/controller gameplay in two owned labs; record both views.

No gameplay state, rooms, items, health or network input frames are fabricated.
The Lua observer only reports state; movement and combat use raw XInput buttons.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
from game_logs import probe_path

SOURCE = Path(__file__).resolve().parents[1]
ROOT = Path("/mnt/d/isaac-lan-lab")
BUTTONS = {
    "u": 1,
    "d": 2,
    "l": 4,
    "r": 8,
    "start": 16,
    "back": 32,
    "lb": 256,
    "rb": 512,
    "a": 4096,
    "b": 8192,
    "x": 16384,
    "y": 32768,
}
ROLES = ("host", "client")


def win(path):
    return subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()


def ps(script, *args):
    result = subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            win(script),
            *map(str, args),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout.strip()


class Gameplay:
    def __init__(self, output, latency_ms=0):
        self.output = output.resolve()
        self.roots = [ROOT / "host-001", ROOT / "client-001"]
        self.latency_ms = latency_ms
        self.processes = []
        self.capture_number = max(
            (
                int(p.name.split("-")[0])
                for p in self.output.glob("*.png")
                if p.name.split("-")[0].isdigit()
            ),
            default=0,
        )
        self.floor_hud = None
        path = self.output / "processes.json"
        if path.exists():
            self.processes = json.loads(path.read_text())

    def log(self, action, **values):
        self.output.mkdir(parents=True, exist_ok=True)
        with (self.output / "actions.jsonl").open("a") as f:
            f.write(json.dumps({"time": time.time(), "action": action, **values}) + "\n")

    def launch(self):
        self.output.mkdir(parents=True, exist_ok=True)
        if any(self.output.iterdir()):
            raise RuntimeError("Use a fresh output directory for each run")
        for root in self.roots:
            if not (root / ".isaac-lan-lab").is_file():
                raise RuntimeError("Unowned lab")
        live = subprocess.check_output(
            [
                "powershell.exe",
                "-NoProfile",
                "-Command",
                "Get-CimInstance Win32_Process -Filter \"Name='isaac-ng.exe'\" | Where-Object { $_.ExecutablePath -match '^D:\\\\isaac-lan-lab\\\\(host-001|client-001)\\\\game\\\\isaac-ng.exe$' } | Select-Object -ExpandProperty ProcessId",
            ],
            text=True,
        )
        if live.strip():
            raise RuntimeError("Owned labs are already running: " + live.strip())
        dll = SOURCE / "build-win32/isaac_lan_probe.dll"
        shutil.copy2(dll, self.output / "tested-probe.dll")
        shutil.copy2(SOURCE / "tests/manual_gameplay.lua", self.output / "observer.lua")
        shutil.copy2(Path(__file__), self.output / "controller.py")
        try:
            for root in self.roots:
                for mod in (root / "game/mods").iterdir():
                    if mod.is_dir():
                        (mod / "disable.it").touch()
                shutil.copy2(self.output / "tested-probe.dll", root / "game/isaac_lan_probe.dll")
                shutil.copy2(self.output / "observer.lua", root / "frontend-scenario.lua")
                (root / "frontend.test").write_text("Normal input and read-only observation.\n")
                (root / "visual-capture.test").touch()
                if (root / "visual-frames").exists():
                    shutil.rmtree(root / "visual-frames")
                for name in [
                    "lan-human-input.json",
                    "lan-human-state.json",
                    "lan-human-floors.jsonl",
                    "lan-test-pad.txt",
                ]:
                    (root / "game" / name).unlink(missing_ok=True)
                profile = root / "profile/Documents/My Games/Binding of Isaac Repentance+"
                (profile / "gamestate1.dat").unlink(missing_ok=True)
                (profile / "log.txt").unlink(missing_ok=True)
                result = subprocess.check_output(
                    [str(root / "isaac_lan_lab.exe"), win(root)], text=True, timeout=30
                )
                match = re.search(r"bootstrap_status=0 pid=(\d+)", result)
                if not match:
                    raise RuntimeError(result)
                self.processes.append(int(match[1]))
                (self.output / "processes.json").write_text(json.dumps(self.processes))
                print(result.strip(), flush=True)
            self.log(
                "launch",
                processes=self.processes,
                dll_sha256=hashlib.sha256(dll.read_bytes()).hexdigest(),
            )
            self.wait(
                lambda: all((r / "game/lan-human-state.json").exists() for r in self.roots), 20
            )
        except BaseException:
            if self.processes:
                self.close()
            raise

    def wait(self, predicate, timeout=15):
        until = time.monotonic() + timeout
        while not predicate():
            if time.monotonic() > until:
                raise RuntimeError("Normal gameplay condition timed out")
            time.sleep(0.05)

    def state(self, role):
        path = self.roots[ROLES.index(role)] / "game/lan-human-state.json"
        for _ in range(10):
            try:
                return json.loads(path.read_text())
            except (OSError, json.JSONDecodeError):
                time.sleep(0.05)
        raise RuntimeError("Observer unavailable: " + role)

    def pad(self, role, buttons="", frames=12, wait=True):
        if not 0 <= frames <= 3600:
            raise ValueError("Duration must be 0..3600 render frames")
        value = sum(BUTTONS[k] for k in set(buttons.split("+")) if k)
        indices = range(2) if role == "both" else [ROLES.index(role)]
        sequence = time.time_ns()
        for i in indices:
            path = self.roots[i] / "game/lan-human-input.json"
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps({"buttons": value, "frames": frames, "sequence": sequence}))
            tmp.replace(path)
        self.log("pad", role=role, buttons=buttons, frames=frames, sequence=sequence)
        if wait:
            self.wait(
                lambda: all(
                    self.state(ROLES[i]).get("sequence") == sequence
                    and self.state(ROLES[i]).get("inputRemaining", 0) == 0
                    for i in indices
                ),
                max(10, frames / 30 + 5),
            )
            time.sleep(0.15)

    def key(self, role, value):
        for i in range(2) if role == "both" else [ROLES.index(role)]:
            ps(
                SOURCE / "tools/lab_window.ps1",
                "-GameProcessId",
                self.processes[i],
                "-Action",
                "PostKeys",
                "-Value",
                value,
            )
        self.log("key", role=role, value=value)

    def capture(self, name):
        # SwapBuffers recording contains actual pixels even for a background
        # window. Never use PrintWindow (it can return a black OpenGL image).
        self.capture_number += 1
        for i, role in enumerate(ROLES):
            directory = self.roots[i] / "visual-frames"
            files = list(directory.glob("*.png"))
            if not files:
                raise RuntimeError("Rendered frames unavailable")
            latest = max(files, key=lambda p: int(p.stem))
            target = self.output / f"{self.capture_number:03}-{name}-{role}.png"
            shutil.copy2(latest, target)
            value = self.state(role)
            target.with_suffix(".json").write_text(json.dumps(value, indent=2))
            self.log(
                "capture", role=role, name=target.name, recorded_frame=int(latest.stem), state=value
            )
        print("captured " + name, flush=True)

    def boot(self, seed="LBCD0G4M"):
        time.sleep(2)
        self.key("both", "{SPACE}")
        time.sleep(0.5)
        self.pad("both", "a")
        time.sleep(1)
        self.pad("both", "a")
        time.sleep(1)
        for b in ("d", "a", "d", "a"):
            self.pad("both", b)
        self.pad("host", "a")
        for b in ("d", "a"):
            self.pad("client", b)
        for key in "127.0.0.1":
            self.key("client", key)
        for b in ("a", "d"):
            self.pad("client", b)
        if self.latency_ms:
            self.pad("client", "a")
            for _ in range(5):
                self.key("client", "{BACKSPACE}")
            for key in "29507":
                self.key("client", key)
            self.pad("client", "a")
        for b in ("d", "a"):
            self.pad("client", b)
        self.wait(
            lambda: all(
                self.state(r)["phase"] == 2 and self.state(r)["players"] == 2 for r in ROLES
            )
        )
        for _ in range(7):
            self.pad("both", "r")
        self.pad("both", "d")
        self.pad("both", "a")
        self.pad("host", "d")
        self.pad("host", "d")
        self.pad("host", "a")
        for key in seed:
            self.key("host", key)
        self.pad("host", "a")
        self.pad("host", "d")
        self.capture("ready-lobby")
        self.pad("host", "a")
        self.wait(lambda: all(self.state(r).get("stage") == 1 for r in ROLES), 30)
        self.log(
            "scenario",
            seed=seed,
            characters=[7, 7],
            connection="127.0.0.1:29506 TCP",
            one_way_latency_ms=self.latency_ms,
            mods="disabled",
        )
        self.capture("start")

    def actor(self, role):
        value = self.state(role)
        controller = value["slot"] + 1
        return next(p for p in value["playersState"] if p["controller"] == controller)

    def walk(self, role, x, y, timeout=20, tolerance=8, stop_when=None):
        until = time.monotonic() + timeout
        stage = self.state(role)["stage"]
        room = self.state(role)["room"]
        while time.monotonic() < until:
            if stop_when and stop_when():
                return
            value = self.state(role)
            if value.get("phase") != 3:
                raise RuntimeError("Session stopped during walking: " + str(value))
            if value.get("room") is None or value.get("stage") is None:
                time.sleep(0.05)
                continue
            if value.get("room") != room or value.get("stage") != stage:
                return
            p = self.actor(role)
            dx = x - p["x"]
            dy = y - p["y"]
            if abs(dx) < tolerance and abs(dy) < tolerance:
                return
            buttons = []
            if abs(dx) >= tolerance:
                buttons.append("r" if dx > 0 else "l")
            if abs(dy) >= tolerance:
                buttons.append("d" if dy > 0 else "u")
            self.pad(role, "+".join(buttons), min(8, max(2, int(max(abs(dx), abs(dy)) / 4))))
        raise RuntimeError(f"Walking blocked: {role}, goal={x},{y}, state={self.state(role)}")

    def door(self, role, slot):
        old = self.state(role)["room"]
        door = next(d for d in self.state(role)["doors"] if d["slot"] == slot)
        if not door["open"]:
            raise RuntimeError("Door is locked")
        # Walk beyond the threshold via ordinary input, never rooms_move.
        dx, dy = {
            0: (-32, 0),
            1: (0, -32),
            2: (32, 0),
            3: (0, 32),
            4: (-32, 0),
            5: (0, -32),
            6: (32, 0),
            7: (0, 32),
        }[slot]
        self.walk(role, door["x"] + dx, door["y"] + dy)
        self.wait(lambda: self.state(role).get("room") == door["target"])
        self.capture(f"{role}-door-{slot}")

    def door_both(self, slot):
        old = self.state("host")["room"]
        if self.state("client")["room"] != old:
            # A player can cross early due to momentum while approaching the
            # threshold. Bring the other through that same ordinary door.
            for role, other in (("host", "client"), ("client", "host")):
                door = next((d for d in self.state(role)["doors"] if d["slot"] == slot), None)
                if door and door["target"] == self.state(other)["room"]:
                    self.door(role, slot)
                    return
            raise RuntimeError("Party must meet before walking through the same door")
        door = next(d for d in self.state("host")["doors"] if d["slot"] == slot)
        dx, dy = {0: (80, 0), 1: (0, 80), 2: (-80, 0), 3: (0, -80)}[slot]
        for role in ROLES:
            self.walk(role, door["x"] + dx, door["y"] + dy)
        self.pad("both", {0: "l", 1: "u", 2: "r", 3: "d"}[slot], 45)
        # Native room/Boss intros can consume rendering frames while a
        # player's movement is blocked. Finish the actual crossing with
        # observed position and ordinary input, not a fixed button duration.
        for role in ROLES:
            self.wait(lambda: self.state(role).get("room") is not None)
            current = self.state(role)["room"]
            if current == door["target"]:
                continue
            if current != old:
                raise RuntimeError("Player entered an unexpected room during shared door crossing")
            self.door(role, slot)
        self.wait(lambda: all(self.state(r).get("room") == door["target"] for r in ROLES))
        self.capture("both-door-" + str(slot))

    def fight(self, role="both", timeout=90):
        active = ROLES if role == "both" else [role]
        until = time.monotonic() + timeout
        rooms = {r: self.state(r)["room"] for r in active}
        while time.monotonic() < until:
            # Releasing a beam can clear a room while a retreat is still held.
            # Stop input and return through an open door if that movement took
            # us into an adjacent cleared room; never treat it as a new route.
            for r in active:
                v = self.state(r)
                if v.get("room") is not None and v["room"] != rooms[r]:
                    self.pad(r, "", 1)
                    door = next(
                        (d for d in v["doors"] if d["target"] == rooms[r] and d["open"]), None
                    )
                    if not door:
                        raise RuntimeError("Combat pilot left its room without an open return door")
                    self.door(r, door["slot"])
            if all(
                self.state(r).get("room") == rooms[r] and self.state(r).get("clear") for r in active
            ):
                self.pad(role, "", 1)
                self.capture("combat-cleared")
                return
            chargeUntil = time.monotonic() + 1.5
            while time.monotonic() < chargeUntil:
                living = 0
                for r in active:
                    v = self.state(r)
                    if v.get("phase") != 3:
                        raise RuntimeError("Party run ended during ordinary combat")
                    if not v.get("playersState"):
                        continue
                    p = self.actor(r)
                    if p.get("ghost") or p["hearts"] + p["soul"] <= 0:
                        continue
                    living += 1
                    # Replicas deliberately disable gameplay collisions, so
                    # IsVulnerableEnemy is false there. This fixed seed uses
                    # ordinary NPCs, fires and invulnerable spike blocks.
                    enemies = [
                        e
                        for e in v["entities"]
                        if e["hp"] > 0
                        and (
                            e.get("active")
                            or r == "client"
                            and 10 <= e["type"] < 1000
                            and e["type"] not in (33, 218)
                        )
                    ]
                    if not enemies:
                        continue
                    e = min(enemies, key=lambda e: (e["x"] - p["x"]) ** 2 + (e["y"] - p["y"]) ** 2)
                    dx = e["x"] - p["x"]
                    dy = e["y"] - p["y"]
                    horizontal = abs(dx) > abs(dy)
                    shoot = ("b" if dx > 0 else "x") if horizontal else ("a" if dy > 0 else "y")
                    along, across = (dx, dy) if horizontal else (dy, dx)
                    move = ""
                    # Do not align a short beam by walking into the enemy.
                    # This also lets the pilot retreat from Monstro's landing
                    # before choosing another firing line.
                    if dx * dx + dy * dy < 90**2:
                        move = ("l" if dx > 0 else "r") if horizontal else ("u" if dy > 0 else "d")
                    elif abs(across) > 12:
                        move = ("d" if dy > 0 else "u") if horizontal else ("r" if dx > 0 else "l")
                    elif abs(along) > 110:
                        move = ("r" if dx > 0 else "l") if horizontal else ("d" if dy > 0 else "u")
                    elif abs(along) < 85:
                        move = ("l" if dx > 0 else "r") if horizontal else ("u" if dy > 0 else "d")
                    # Use observed projectile motion to sidestep an approaching
                    # shot, rather than holding a stale aim while it hits us.
                    shots = [
                        q
                        for q in v["entities"]
                        if q["type"] == 9
                        and (q["x"] + q.get("vx", 0) * 6 - p["x"]) ** 2
                        + (q["y"] + q.get("vy", 0) * 6 - p["y"]) ** 2
                        < 60**2
                    ]
                    if shots:
                        q = min(
                            shots, key=lambda q: (q["x"] - p["x"]) ** 2 + (q["y"] - p["y"]) ** 2
                        )
                        if abs(q.get("vx", 0)) > abs(q.get("vy", 0)):
                            move = "u" if p["y"] < q["y"] else "d"
                        else:
                            move = "l" if p["x"] < q["x"] else "r"
                    # Do not retreat into a wall until pursuing enemies reach
                    # us. A perpendicular dodge still keeps the beam charging.
                    center = v["center"]
                    blocked = (
                        move == "l"
                        and p["x"] < 75
                        or move == "r"
                        and p["x"] > 2 * center["x"] - 75
                        or move == "u"
                        and p["y"] < 155
                        or move == "d"
                        and p["y"] > 2 * center["y"] - 155
                    )
                    if blocked:
                        move = (
                            ("u" if p["y"] > center["y"] else "d")
                            if horizontal
                            else ("l" if p["x"] > center["x"] else "r")
                        )
                    self.pad(r, shoot + ("+" + move if move else ""), 18, False)
                if not living:
                    raise RuntimeError("No living combatants")
                time.sleep(0.15)
            for r in active:
                self.pad(r, "", 1, False)
            time.sleep(0.4)
        raise RuntimeError("Normal combat did not clear the room in time")

    def run(self):
        self.boot()
        self.door("host", 1)
        self.walk("host", 320, 305)
        self.capture("treasure-pickup")
        self.door("client", 1)
        time.sleep(2)
        self.capture("guest-body-after-door")
        self.pad("both", "rb")
        self.wait(lambda: all(self.state(r).get("room") == 84 for r in ROLES))
        self.capture("fool-return")
        self.door_both(2)
        self.fight()
        self.door_both(2)
        self.fight()
        self.capture("large-room-clear")
        # Normal exploration, including separate rooms and returning to meet.
        if self.actor("client")["keys"] > 0:
            self.door("client", 3)
            self.capture("shop-separated")
            self.door("client", 1)
        self.door_both(2)
        # Moving spike blocks are invulnerable. Cross their room along the
        # north corridor, using ordinary movement, then meet at the boss door.
        for role in ROLES:
            self.walk(role, 90, 180)
            self.walk(role, 520, 180)
            self.walk(role, 520, 280)
        self.door_both(2)
        self.fight(timeout=120)
        self.capture("boss-cleared")
        if any(
            self.actor(r)["ghost"] or self.actor(r)["hearts"] + self.actor(r)["soul"] <= 0
            for r in ROLES
        ):
            raise RuntimeError(
                "Combat driver lost a player; this run cannot verify the two-player reward flow"
            )
        total = lambda: sum(self.actor(r)["collectibles"] for r in ROLES)
        rewardStart = total()
        for role in ("client", "host"):
            # Original co-op allows one player to take consecutive rewards.
            # Check the party's two-item gain, rather than forcing one each.
            if total() >= rewardStart + 2:
                break
            self.wait(
                lambda: total() >= rewardStart + 2
                or any(
                    e["type"] == 5 and e["variant"] == 100 and e["subtype"] > 0
                    for e in self.state(role)["entities"]
                )
            )
            if total() >= rewardStart + 2:
                break
            items = [
                e
                for e in self.state(role)["entities"]
                if e["type"] == 5 and e["variant"] == 100 and e["subtype"] > 0
            ]
            if not items:
                raise RuntimeError("Boss did not provide the next party reward")
            count = self.actor(role)["collectibles"]
            item = items[0]
            # The native trapdoor is already open. Reach the reward via a
            # side corridor instead of walking through the floor exit.
            side = 180 if self.actor(role)["x"] < 320 else 460
            self.walk(role, side, self.actor(role)["y"])
            self.walk(role, side, item["y"])
            self.walk(
                role,
                item["x"],
                item["y"],
                stop_when=lambda: self.actor(role)["collectibles"] > count,
            )
            self.wait(lambda: self.actor(role)["collectibles"] > count)
            self.capture(role + "-boss-reward")
        self.wait(lambda: total() >= rewardStart + 2)
        self.capture("party-boss-rewards")
        self.pad("host", "start")
        self.wait(lambda: self.state("client")["pause"] == 1)
        self.capture("pause")
        self.pad("host", "start")
        self.wait(lambda: self.state("client")["pause"] == 0)
        from check_floor_hud import FloorHudWatch

        self.floor_hud = FloorHudWatch(self.processes, ROLES, self.output)
        self.walk("client", 320, 200)
        self.wait(lambda: all(self.state(r).get("stage") == 2 for r in ROLES), 30)
        self.capture("second-floor")
        self.floor_hud.finish()
        self.door("client", 2)
        self.capture("second-floor-first-door")
        # Large-room camera smoothing must converge after normal arrival,
        # even with the host remaining behind in the starting room.
        self.pad("client", "b", 120)
        self.capture("second-floor-arrival-settled")
        screen = self.state("client")["localScreen"]
        if not (0 <= screen["x"] <= 480 and 0 <= screen["y"] <= 270):
            raise RuntimeError("Local actor outside the isolated 480x270 viewport: " + str(screen))
        self.pad("host", "start")
        self.wait(lambda: self.state("client")["pause"] == 1)
        self.capture("final-paused")
        for root in self.roots:
            log = root / "profile/Documents/My Games/Binding of Isaac Repentance+/log.txt"
            if "Error in" in log.read_text(errors="replace"):
                raise RuntimeError("Game callback error in " + str(root))

    def close(self):
        if self.floor_hud is not None:
            self.floor_hud.stop()
        # Freeze both peers before closing either one can change the other's state.
        for i, pid in enumerate(self.processes):
            root = self.roots[i]
            role = ROLES[i]
            for path, name in [
                (root / "game/lan-human-state.json", f"{role}-final-state.json"),
                (root / "game/lan-human-floors.jsonl", f"{role}-floors.jsonl"),
                (probe_path(root), f"{role}-probe-before-close.log"),
                (
                    root / "profile/Documents/My Games/Binding of Isaac Repentance+/log.txt",
                    f"{role}-game-before-close.log",
                ),
            ]:
                if path.exists():
                    shutil.copy2(path, self.output / name)
            native = probe_path(root)
            if native.exists():
                (self.output / f"{role}-probe-this-run.log").write_text(
                    native.read_text(errors="replace").rsplit("bootstrap=PASS", 1)[-1]
                )
        failures = []
        closed = []
        for i, pid in enumerate(self.processes):
            try:
                ps(SOURCE / "tools/lab_window.ps1", "-GameProcessId", pid, "-Action", "Close")
            except Exception as e:
                failures.append(f"{ROLES[i]} close: {e}")
                continue
            closed.append(i)
        # Stop both recordings before potentially slow cross-volume copies.
        for i in closed:
            root = self.roots[i]
            try:
                (root / "frontend-scenario.lua").unlink(missing_ok=True)
                (root / "visual-capture.test").unlink(missing_ok=True)
                if (root / "visual-frames").exists():
                    shutil.move(str(root / "visual-frames"), self.output / f"{ROLES[i]}-frames")
            except Exception as e:
                failures.append(f"{ROLES[i]} recording cleanup: {e}")
        if failures:
            self.log("close-failed", errors=failures)
            raise RuntimeError("; ".join(failures))
        path = self.output / "processes.json"
        if path.exists():
            path.rename(self.output / "closed-processes.json")
        self.log("close")

    def report(self, error=None):
        errors = []
        floors = {}
        for role in ROLES:
            path = self.output / f"{role}-game-before-close.log"
            if path.exists():
                errors.extend(
                    role + ": " + s
                    for s in path.read_text(errors="replace").splitlines()
                    if "Error in" in s or "callback failed" in s
                )
            path = self.output / f"{role}-probe-this-run.log"
            if path.exists():
                errors.extend(
                    role + ": " + s
                    for s in path.read_text(errors="replace").splitlines()
                    if any(
                        t in s
                        for t in (
                            "network_failure=",
                            "frontend_error=",
                            "native_exception",
                            "rooms_fatal=",
                        )
                    )
                )
            path = self.output / f"{role}-floors.jsonl"
            if path.exists():
                trace = [json.loads(line) for line in path.read_text().splitlines()]
                began = next((t["time"] for t in trace if not t["ready"]), None)
                loaded = next((t["time"] for t in trace if t["ready"] and t["stage"] == 2), None)
                floors[role] = {"began": began, "loaded": loaded}
        if error is None and len(floors) == 2:
            if (
                any(t["began"] is None or t["loaded"] is None for t in floors.values())
                or floors["client"]["began"] >= floors["host"]["loaded"]
            ):
                errors.append(
                    "Guest did not begin the native transition before the host finished loading"
                )
        value = {
            "completed": error is None and not errors,
            "failure": error,
            "game_errors": errors,
            "visual_review_required": True,
            "dll_sha256": hashlib.sha256(
                (self.output / "tested-probe.dll").read_bytes()
            ).hexdigest(),
            "method": "Normal menu and raw controller input; read-only observer; actual OpenGL rendered frames at up to 10 fps.",
            "one_way_latency_ms": self.latency_ms,
            "floor_timing": floors,
            "limits": [
                "Same-machine loopback with optional TCP delay, not actual frp",
                "Equal configuration with additional Mods disabled",
                "10 fps may miss a one-frame flash; successful state assertions do not prove visual correctness",
            ],
        }
        (self.output / "report.json").write_text(json.dumps(value, indent=2))
        print(json.dumps(value), flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "action",
        choices=[
            "run",
            "launch",
            "boot",
            "pad",
            "key",
            "capture",
            "state",
            "walk",
            "door",
            "fight",
            "close",
        ],
    )
    ap.add_argument("role", nargs="?", choices=[*ROLES, "both"], default="both")
    ap.add_argument("--output", type=Path, default=SOURCE / "artifacts/normal-gameplay-current")
    ap.add_argument("--buttons", default="")
    ap.add_argument("--frames", type=int, default=12)
    ap.add_argument("--value", default="")
    ap.add_argument("--name", default="screen")
    ap.add_argument("--seed", default="LBCD0G4M")
    ap.add_argument("--x", type=float)
    ap.add_argument("--y", type=float)
    ap.add_argument("--slot", type=int)
    ap.add_argument(
        "--ffmpeg",
        type=Path,
        help="After a full run, archive losslessly and create automatic visual filmstrips",
    )
    ap.add_argument(
        "--latency-ms", type=int, default=0, help="Add this one-way TCP delay during a complete run"
    )
    args = ap.parse_args()
    if args.latency_ms and (args.action != "run" or not 0 < args.latency_ms <= 1000):
        ap.error("--latency-ms requires run and a delay of 1..1000 ms")
    g = Gameplay(args.output, args.latency_ms)
    if args.action == "run":
        error = None
        relay = None
        try:
            if args.latency_ms:
                from delayed_relay import DelayedRelay

                relay = DelayedRelay(29507, 29506, args.latency_ms)
            g.launch()
            g.run()
            if relay and relay.error:
                raise RuntimeError(relay.error)
        except BaseException as e:
            error = f"{type(e).__name__}: {e}"
            raise
        finally:
            if (g.output / "processes.json").exists():
                # Closing the host changes the guest's observer to the lobby.
                # Freeze both final states before either process is closed.
                for role in ROLES:
                    try:
                        (g.output / (role + "-final-observer.json")).write_text(
                            json.dumps(g.state(role), indent=2) + "\n"
                        )
                    except Exception as e:
                        g.log("final-observer-unavailable", role=role, error=str(e))
                try:
                    g.close()
                except Exception as e:
                    error = (error + "; " if error else "") + str(e)
            if relay:
                relay.close()
            g.report(error)
            if args.ffmpeg and not (g.output / "processes.json").exists():
                from archive_gameplay import archive
                from review_gameplay import review

                archive(g.output, args.ffmpeg)
                review(g.output, args.ffmpeg)
            if error:
                raise RuntimeError(error)
    elif args.action == "launch":
        g.launch()
    elif args.action == "boot":
        g.boot(args.seed)
    elif args.action == "pad":
        g.pad(args.role, args.buttons, args.frames)
    elif args.action == "key":
        g.key(args.role, args.value)
    elif args.action == "capture":
        g.capture(args.name)
    elif args.action == "state":
        for role in ROLES if args.role == "both" else [args.role]:
            print(role + ": " + json.dumps(g.state(role)))
    elif args.action == "walk":
        g.walk(args.role, args.x, args.y)
        g.capture("walk")
    elif args.action == "door":
        g.door(args.role, args.slot)
    elif args.action == "fight":
        g.fight(args.role)
    elif args.action == "close":
        g.close()
        g.report()


if __name__ == "__main__":
    main()
