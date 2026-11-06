"""Owned manual-session setup and supervision, independent of the CLI entry point."""

from contextlib import ExitStack
import configparser
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from datagram_relay import DatagramRelay
from game_logs import freeze_probe_logs, log_path
from lab_profile import ProtectedLabs, idle, validate_startup, windows
from testing.lua import literal

ROOT = Path(__file__).resolve().parents[1]
ROLES = ("host", "client")
STARTUP_TIMEOUT = 120
MAX_RTT_MS = 10000
FIRST_HOST_PORT, LAST_HOST_PORT = 29506, 29606
DEFAULT_LABS = tuple(Path("/mnt/d/isaac-lan-lab") / (role + "-001") for role in ROLES)
LATEST = ROOT / "test-runs/manual-dual/latest.json"


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def normalize(name):
    return re.sub(r"[\s·_\-'’]", "", name).casefold().removeprefix("player")


def character_names():
    # Reuse the menu's translated names; numeric IDs remain owned by game PlayerType.
    source = (ROOT / "src/bridge/presentation/menu.lua").read_text(encoding="utf-8")
    names = re.findall(r'\[PlayerType\.(PLAYER_\w+)\] = "([^"]+)"', source)
    if not names:
        raise ValueError("Could not read the menu character catalogue")
    return names


def character(value):
    if value.isdecimal() and 0 <= int(value) <= 65535:
        return int(value)
    aliases = {}
    for symbol, chinese in character_names():
        for name in (symbol, chinese):
            aliases.setdefault(normalize(name), symbol)
        if symbol.endswith("_B"):
            aliases[normalize("tainted-" + symbol.removeprefix("PLAYER_")[:-2])] = symbol
    try:
        return aliases[normalize(value)]
    except KeyError:
        raise ValueError(
            f"未知角色 {value!r}；用 --list-characters 查看名称，也可传 PlayerType 数字"
        ) from None


def latency(value):
    result = float(value)
    if not math.isfinite(result) or not 0 <= result <= MAX_RTT_MS:
        raise ValueError(f"往返延迟必须是 0..{MAX_RTT_MS} ms")
    return result


def validate_manual_labs(labs, output):
    # Unlike automated acceptance, this explicit manual launcher may use host/client-001.
    if len(labs) != 2 or labs[0] == labs[1]:
        raise ValueError("需要两个不同的隔离目录")
    for lab in labs:
        if not (lab / ".isaac-lan-lab").is_file() or not (lab / "game/isaac-ng.exe").is_file():
            raise ValueError(f"缺少有归属标记的隔离副本：{lab}；先用 tools/prepare_lab.py 准备")
        if output.is_relative_to(lab) or lab.is_relative_to(output):
            raise ValueError("运行记录必须位于隔离目录之外")
        if any(other != lab and lab.is_relative_to(other) for other in labs):
            raise ValueError("隔离目录不能相互包含")
    validate_startup(labs)
    idle(labs)


class SetupFiles:
    """Restore temporary startup flags and fixture enablement after both peers exit."""

    def __init__(self, output):
        self.output, self.entries = output, {}

    def remember(self, path):
        if path in self.entries:
            return
        backup = self.output / f"setup-before/{len(self.entries)}"
        if path.exists():
            if not path.is_file() or path.is_symlink():
                raise ValueError(f"Expected a regular setup file: {path}")
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
            self.entries[path] = backup
        else:
            self.entries[path] = None
        write_json(
            self.output / "setup-backup.json",
            {str(source): str(saved) if saved else None for source, saved in self.entries.items()},
        )

    def remove(self, path):
        self.remember(path)
        path.unlink(missing_ok=True)

    def write(self, path, text):
        self.remember(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def restore(self):
        for path, backup in self.entries.items():
            if backup:
                shutil.copy2(backup, path)
                if path.read_bytes() != backup.read_bytes():
                    raise RuntimeError(f"Setup restore differs: {path}")
            else:
                path.unlink(missing_ok=True)


def configure_options(lab, slot):
    path = log_path(lab).parent / "options.ini"
    options = configparser.ConfigParser()
    options.optionxform = str
    options.read(path, encoding="utf-8-sig")
    values = options["Options"]
    values.update(
        SteamCloud="0",
        Fullscreen="0",
        PauseOnFocusLost="0",
        MusicEnabled="1",
        WindowWidth="920",
        WindowHeight="540",
        WindowPosX=str(16 + slot * 952),
        WindowPosY="16",
    )
    for name in ("MusicVolume", "SFXVolume"):
        if float(values.get(name, "0")) <= 0:
            values[name] = "0.2000"
    with path.open("w", encoding="utf-8") as stream:
        options.write(stream, space_around_delimiters=False)


def prepare(lab, slot, config, files):
    build = Path(config["build"])
    loader, marker = lab / "game/winmm.dll", lab / "game/.isaac-lan-loader"
    if loader.exists() and not marker.is_file():
        raise ValueError("Refusing to replace an unowned winmm.dll: " + str(loader))
    files.remove(loader)
    files.remove(marker)
    for flag in lab.glob("*.test"):
        files.remove(flag)
    for mod in (lab / "game/mods").glob("*"):
        if mod.is_dir() and (
            mod.name == "lan_native_internal_probe" or (mod / ".lan-compat-fixture").is_file()
        ):
            files.write(mod / "disable.it", "")
    shutil.copy2(build / "isaac_lan_probe.dll", lab / "game/isaac_lan_probe.dll")
    shutil.copy2(build / "isaac_lan_lab.exe", lab / "isaac_lan_lab.exe")
    configure_options(lab, slot)
    files.remove(lab / "game/manual-dual-ready.json")
    files.remove(lab / "game/manual-dual-ready.json.tmp")
    files.write(lab / "frontend.test", "Owned manual startup; no gameplay automation.\n")
    bootstrap = (ROOT / "tools/manual_dual_bootstrap.lua").read_text(encoding="utf-8")
    settings = {
        "host": slot == 0,
        "session": config["session"],
        "character": config["characters"][slot],
        "port": config["host_port"] if slot == 0 else config["relay_port"],
    }
    files.write(
        lab / "frontend-scenario.lua",
        "(function()\n" + bootstrap + "\nend)()(" + literal(settings) + ")\n",
    )


def processes():
    command = (
        "@(Get-Process -Name isaac-ng -ErrorAction SilentlyContinue | ForEach-Object { "
        "@{pid=$_.Id; path=$_.Path; started=$_.StartTime.ToUniversalTime().Ticks.ToString()} "
        "}) | ConvertTo-Json -Compress"
    )
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    )
    value = json.loads(result.stdout or "[]") or []
    return [value] if isinstance(value, dict) else value


def choose_host_port():
    # Probe on Windows, where the host binds. A Linux reservation can make WSL's
    # localhost forwarding occupy that port on Windows even after it is closed.
    command = (
        "$ErrorActionPreference='Stop'; "
        f"foreach ($port in {FIRST_HOST_PORT}..{LAST_HOST_PORT}) {{ "
        "$probe=New-Object System.Net.Sockets.UdpClient; try { "
        "$probe.Client.ExclusiveAddressUse=$true; "
        "$probe.Client.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Any,$port)); "
        "Write-Output $port; exit 0 "
        "} catch { } finally { $probe.Dispose() } }; throw 'No free manual host port'"
    )
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        check=True,
        timeout=20,
    )
    return int(result.stdout.strip())


def identity(process):
    return process["pid"], process["path"].casefold(), process["started"]


def live_owned(owned):
    live = {identity(process) for process in processes()}
    return [process for process in owned if identity(process) in live]


def launch(lab, role, output):
    result = subprocess.run(
        [str(lab / "isaac_lan_lab.exe"), windows(lab)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=40,
    )
    text = result.stdout.decode("utf-8", errors="replace")
    (output / f"{role}-launch.log").write_text(text, encoding="utf-8")
    match = re.search(r"bootstrap_status=0 pid=(\d+)", text)
    if result.returncode or not match:
        raise RuntimeError(f"{role} 启动失败：{text}")
    expected = windows(lab / "game/isaac-ng.exe").casefold()
    try:
        for process in processes():
            if process["pid"] == int(match[1]) and process["path"].casefold() == expected:
                return dict(process, role=role)
    except Exception:
        # The runner just created this PID in a previously idle, locked lab.
        # An inspection failure must not orphan it before the caller records it.
        request_close({"pid": int(match[1]), "path": expected, "role": role}, output)
        raise
    raise RuntimeError(f"{role} 在启动器返回后退出；详见 {output}")


def request_close(process, output):
    result = subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            windows(ROOT / "tools/lab_owned_exit.ps1"),
            "-GameProcessId",
            str(process["pid"]),
            "-ExpectedExecutable",
            process["path"],
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=True,
    )
    (output / (process["role"] + "-close.log")).write_text(result.stdout, encoding="utf-8")


def close_owned(owned, output):
    if not owned:
        return
    for process in live_owned(owned):
        request_close(process, output)


def readiness(labs, session):
    result = {}
    for role, lab in zip(ROLES, labs):
        value = read_json(lab / "game/manual-dual-ready.json")
        if value.get("session") != session or value.get("role") != role:
            continue
        if value.get("error"):
            raise RuntimeError(role + ": " + value["error"])
        if value.get("ready"):
            result[role] = value
    return result if len(result) == 2 else None


def supervisor_alive(state, output):
    try:
        arguments = (
            Path(f"/proc/{int(state['supervisor_pid'])}/cmdline").read_bytes().decode().split("\0")
        )
        return arguments[arguments.index("--worker") + 1] == str(output)
    except (OSError, KeyError, ValueError, IndexError):
        return False


def archive_logs(labs, owned, output):
    for process, lab in zip(owned, labs):
        destination = output / process["role"]
        freeze_probe_logs(lab, destination, process["pid"])
        if log_path(lab).exists():
            shutil.copy2(log_path(lab), destination / "log.txt")
        handoff = lab / "game/manual-dual-ready.json"
        if handoff.exists():
            shutil.copy2(handoff, destination / "handoff.json")


def recover(output):
    """Explicit stop can finish a dead supervisor's recorded transaction."""
    state = read_json(output / "session.json")
    if supervisor_alive(state, output):
        raise RuntimeError("后台仍在运行，应由原后台收尾")
    labs = [Path(value) for value in state["labs"]]
    with ExitStack() as locks:
        for lab in sorted(labs):
            lock = locks.enter_context((lab / ".manual-dual.lock").open("a"))
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        close_owned(state.get("processes", []), output)
        idle(labs)
        archive_logs(labs, state.get("processes", []), output)
        protected = ProtectedLabs.from_backup(labs, output)
        files = SetupFiles(output)
        for path, saved in read_json(output / "setup-backup.json").items():
            source = Path(path)
            backup = Path(saved) if saved else None
            if not any(source.is_relative_to(lab) for lab in labs) or (
                backup and not backup.is_relative_to(output / "setup-before")
            ):
                raise ValueError("Temporary-file backup does not match the selected labs")
            files.entries[source] = backup
        write_json(output / "restored.json", protected.restore())
        files.restore()
        state.update(status="closed", restored=True, recovered=True, updated_at=time.time())
        state.pop("cleanup_error", None)
        write_json(output / "session.json", state)
    return state


def supervise(output):
    config = read_json(output / "config.json")
    labs = [Path(value) for value in config["labs"]]
    state = dict(config, status="starting", supervisor_pid=os.getpid(), processes=[])
    files, protected, relay = SetupFiles(output), None, None
    handed_off = False

    def publish():
        state["updated_at"] = time.time()
        write_json(output / "session.json", state)

    with ExitStack() as locks:
        try:
            validate_manual_labs(labs, output)
            for lab in sorted(labs):
                lock = locks.enter_context((lab / ".manual-dual.lock").open("a"))
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            idle(labs)
            protected = ProtectedLabs(labs, output)
            write_json(output / "backup.json", protected.report())
            config["host_port"] = choose_host_port()
            relay = DatagramRelay(0, config["host_port"], config["latency_ms"] / 2)
            config["relay_port"] = relay.listener.getsockname()[1]
            state.update(host_port=config["host_port"], relay_port=config["relay_port"])
            for slot, lab in enumerate(labs):
                prepare(lab, slot, config, files)
            publish()
            for role, lab in zip(ROLES, labs):
                state["processes"].append(launch(lab, role, output))
                publish()
            deadline = time.monotonic() + STARTUP_TIMEOUT
            while True:
                if (output / "stop").exists():
                    close_owned(state["processes"], output)
                    break
                active = live_owned(state["processes"])
                if not active:
                    if not handed_off:
                        raise RuntimeError("两个实例在交接前退出")
                    break
                if not handed_off:
                    if len(active) != 2:
                        raise RuntimeError("一个实例在交接前退出")
                    ready = readiness(labs, config["session"])
                    if ready:
                        state.update(status="ready", peers=ready)
                        write_json(output / "handoff.json", ready)
                        # The Lua hook has restored itself; remove the on-disk startup script too.
                        for lab in labs:
                            (lab / "frontend-scenario.lua").unlink(missing_ok=True)
                        handed_off = True
                    elif time.monotonic() > deadline:
                        raise TimeoutError("联机开局超时；检查双端启动与游戏日志")
                if relay.error:
                    state.update(status="error", error="UDP relay: " + relay.error)
                    if not handed_off:
                        raise RuntimeError(state["error"])
                state["relay"] = relay.settings()
                publish()
                time.sleep(1)
            state["status"] = "closed"
        except Exception as error:
            state.update(status="error", error=str(error))
            publish()
            if not handed_off:
                close_owned(state["processes"], output)
        finally:
            try:
                if relay:
                    relay.close()
                if protected:
                    idle(labs)
                    archive_logs(labs, state["processes"], output)
                    write_json(output / "restored.json", protected.restore())
                    files.restore()
                    state["restored"] = True
            except Exception as error:
                state.update(status="error", cleanup_error=str(error), restored=False)
            publish()
    return 0 if state["status"] == "closed" else 1
