#!/usr/bin/env python3
"""Compile project Python and Lua scripts without starting the game."""

from pathlib import Path
import shutil
import py_compile
import subprocess
import tempfile

from build_gameplay_suite import build

ROOT = Path(__file__).resolve().parents[1]
LUAC = shutil.which("luac5.3") or "luac"


def main():
    files = (
        subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
        )
        .decode()
        .split("\0")
    )
    for name in sorted(set(files)):
        if name.endswith(".py"):
            py_compile.compile(str(ROOT / name), doraise=True)
        elif name.endswith(".lua"):
            subprocess.run([LUAC, "-p", str(ROOT / name)], check=True)
    with tempfile.TemporaryDirectory() as temporary:
        suite = Path(temporary) / "gameplay.lua"
        build(suite)
        subprocess.run([LUAC, "-p", str(suite)], check=True)
    print("PASS Python, Lua and bundled gameplay syntax")


if __name__ == "__main__":
    main()
