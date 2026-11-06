#!/usr/bin/env python3
"""双开手动测试：指定主客机角色及增加的往返延迟，自动开局后交回操作。"""

import argparse
from datetime import datetime
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

from manual_dual import (
    DEFAULT_LABS,
    LATEST,
    ROOT,
    STARTUP_TIMEOUT,
    character,
    character_names,
    latency,
    read_json,
    recover,
    supervise,
    supervisor_alive,
    validate_manual_labs,
    write_json,
)


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument(
        "--characters",
        nargs=2,
        default=["以撒", "以撒"],
        metavar=("主机", "客机"),
        help="中文名、英文名、PLAYER_* 或数字 PlayerType；默认均为以撒",
    )
    result.add_argument(
        "--latency-ms",
        type=latency,
        default=0,
        metavar="RTT",
        help="额外往返延迟，默认 0；80 表示每方向 40 ms",
    )
    actions = result.add_mutually_exclusive_group()
    actions.add_argument("--status", action="store_true", help="查看最近一次双开的状态")
    actions.add_argument("--stop", action="store_true", help="关闭本工具启动的两端并恢复隔离资料")
    actions.add_argument("--list-characters", action="store_true", help="列出菜单角色名称")
    advanced = result.add_argument_group("隔离环境与运行记录")
    advanced.add_argument("--host", type=Path, default=DEFAULT_LABS[0])
    advanced.add_argument("--client", type=Path, default=DEFAULT_LABS[1])
    advanced.add_argument("--build", type=Path, default=ROOT / "build-win32")
    advanced.add_argument(
        "--output", type=Path, help="新的运行记录目录；默认 test-runs/manual-dual/时间戳"
    )
    advanced.add_argument("--session", type=Path, help="--status/--stop 指定的运行记录目录")
    advanced.add_argument("--skip-build", action="store_true", help="使用已有构建；默认先增量构建")
    result.add_argument("--worker", type=Path, help=argparse.SUPPRESS)
    return result


def existing(args):
    directory = args.session or read_json(LATEST).get("directory")
    if not directory:
        raise ValueError("没有已记录的双开；可用 --session 指定运行目录")
    directory = Path(directory).resolve()
    state = read_json(directory / "session.json")
    if not state:
        raise ValueError("找不到 session.json：" + str(directory))
    if args.stop and not state.get("restored") and state["status"] != "closed":
        if not supervisor_alive(state, directory):
            state = recover(directory)
        (directory / "stop").touch()
        deadline = time.monotonic() + STARTUP_TIMEOUT
        while not state.get("restored"):
            if time.monotonic() > deadline:
                raise TimeoutError("收尾超时，备份已保留：" + str(directory))
            time.sleep(0.5)
            state = read_json(directory / "session.json")
            if state.get("cleanup_error"):
                break
    print(f"状态：{state['status']}；记录：{directory}")
    for process in state.get("processes", []):
        print(f"{process['role']}: PID {process['pid']}")
    for key in ("error", "cleanup_error"):
        if state.get(key):
            print(state[key])
    return int(bool(state.get("cleanup_error")))


def start(args):
    selections = [character(value) for value in args.characters]
    labs = [args.host.resolve(), args.client.resolve()]
    output = (
        args.output or ROOT / "test-runs/manual-dual" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    ).resolve()
    validate_manual_labs(labs, output)
    if output.exists():
        raise ValueError("运行目录已存在，请使用新目录：" + str(output))
    build = args.build.resolve()
    if not args.skip_build:
        subprocess.run(
            [
                "cmake",
                "--build",
                str(build),
                "--target",
                "isaac_lan_probe",
                "isaac_lan_lab",
                "--parallel",
                "4",
            ],
            cwd=ROOT,
            check=True,
        )
    for name in ("isaac_lan_probe.dll", "isaac_lan_lab.exe"):
        if not (build / name).is_file():
            raise ValueError("缺少构建产物：" + str(build / name))
    output.mkdir(parents=True)
    frozen = output / "build"
    frozen.mkdir()
    for name in ("isaac_lan_probe.dll", "isaac_lan_lab.exe"):
        shutil.copy2(build / name, frozen / name)
    config = {
        "session": uuid.uuid4().hex,
        "labs": [str(lab) for lab in labs],
        "build": str(frozen),
        "source_build": str(build),
        "characters": selections,
        "character_names": args.characters,
        "latency_ms": args.latency_ms,
        "dll_sha256": hashlib.sha256((frozen / "isaac_lan_probe.dll").read_bytes()).hexdigest(),
    }
    write_json(output / "config.json", config)
    print("正在双开，运行记录：" + str(output), flush=True)
    with (output / "supervisor.log").open("w", encoding="utf-8") as log:
        worker = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "--worker", str(output)],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    try:
        deadline = time.monotonic() + STARTUP_TIMEOUT + 90
        while time.monotonic() < deadline:
            state = read_json(output / "session.json")
            if state.get("status") == "ready":
                LATEST.parent.mkdir(parents=True, exist_ok=True)
                write_json(LATEST, {"directory": str(output)})
                for slot, role in enumerate(("host", "client")):
                    print(
                        f"{role}: {args.characters[slot]}，PID {state['processes'][slot]['pid']}，Ping {state['peers'][role]['ping_ms']} ms"
                    )
                print(
                    f"已进入游戏并交回手动操作。额外 RTT {args.latency_ms:g} ms；关闭两窗口后自动收尾。"
                )
                return 0
            if worker.poll() is not None:
                raise RuntimeError(
                    state.get("error", "启动后台退出；查看 supervisor.log")
                    + "；记录："
                    + str(output)
                )
            time.sleep(0.25)
        raise TimeoutError("启动超时；记录：" + str(output))
    except BaseException:
        (output / "stop").touch()
        raise


def main():
    args = parser().parse_args()
    try:
        if args.worker:
            return supervise(args.worker.resolve())
        if args.list_characters:
            for symbol, name in character_names():
                print(f"{name}\t{symbol}")
            return 0
        if args.status or args.stop:
            return existing(args)
        return start(args)
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
