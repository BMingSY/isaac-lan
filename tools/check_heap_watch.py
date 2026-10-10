#!/usr/bin/env python3
"""Exercise full-dump capture with a synthetic process; never launch Isaac."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time


def windows_path(path):
    return (
        str(path.resolve())
        if os.name == "nt"
        else subprocess.check_output(["wslpath", "-w", str(path.resolve())], text=True).strip()
    )


def check(build, output):
    output.mkdir(parents=True, exist_ok=True)
    # On WSL use the native temporary directory so the fixture never modifies
    # a real game tree. On Windows the ordinary temporary directory suffices.
    temporary = (
        None
        if os.name == "nt"
        else subprocess.check_output(
            ["powershell.exe", "-NoProfile", "-Command", "[IO.Path]::GetTempPath()"], text=True
        ).strip()
    )
    if temporary:
        temporary = subprocess.check_output(["wslpath", "-u", temporary], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="isaac-lan-heap-fixture-", dir=temporary) as directory:
        root = Path(directory)
        (root / ".isaac-lan-lab").write_text("Synthetic heap observer test only.\n")
        (root / "game").mkdir()
        executable = root / "game/isaac-ng.exe"
        shutil.copy2(build / "isaac_lan_heap_fixture.exe", executable)
        fixture = subprocess.Popen(
            [str(executable)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
        )
        watcher = None
        try:
            pid = int(re.fullmatch(r"fixture_pid=(\d+)\s*", fixture.stdout.readline())[1])
            with (output / "observer.log").open("wb") as stream:
                watcher = subprocess.Popen(
                    [
                        str(build / "isaac_lan_heap_watch.exe"),
                        windows_path(root),
                        windows_path(root / "dumps"),
                        str(pid),
                    ],
                    stdout=stream,
                    stderr=subprocess.STDOUT,
                )
                deadline = time.monotonic() + 10
                while f"heap_watch_ready pid={pid}" not in (output / "observer.log").read_text(
                    errors="replace"
                ):
                    if watcher.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("Heap observer fixture did not initialize")
                    time.sleep(0.05)
                (root / "go").touch()
                fixture.wait(timeout=20)
                watcher.wait(timeout=20)
            text = (output / "observer.log").read_text(errors="replace")
            dumps = list((root / "dumps").glob("*.dmp"))
            assert "code=c0000374" in text and "result=PASS" in text
            assert f"heap_game_exit pid={pid} code=c0000374" in text
            assert watcher.returncode == 5 and len(dumps) == 1
            assert all(path.stat().st_size > 16384 for path in dumps)
            report = {"passed": True, "synthetic": True, "pid": pid, "dump_count": len(dumps)}
            (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
            return report
        finally:
            for process in (fixture, watcher):
                if process is not None and process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
            fixture.stdout.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(check(args.build.resolve(), args.output.resolve()), indent=2))
