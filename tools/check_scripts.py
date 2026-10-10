#!/usr/bin/env python3
"""Compile project Python and Lua scripts without starting the game."""

from pathlib import Path
import shutil
import py_compile
import subprocess
import tempfile

from build_gameplay_suite import build
from build_ending_suite import build as build_endings
from build_special_suite import build as build_special

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
        endings = Path(temporary) / "endings.lua"
        build_endings(endings)
        subprocess.run([LUAC, "-p", str(endings)], check=True)
        build_endings(endings, ["ascent"])
        subprocess.run([LUAC, "-p", str(endings)], check=True)
        special = Path(temporary) / "special.lua"
        build_special(special)
        subprocess.run([LUAC, "-p", str(special)], check=True)
        build_special(
            special, ["motion", "floor-items", "mod-integrations", "shared-curses", "ascent-compat"]
        )
        subprocess.run([LUAC, "-p", str(special)], check=True)
        build_special(special, ["lanbot", "lanbot-campaign"])
        subprocess.run([LUAC, "-p", str(special)], check=True)
        build_special(special, ["greed", "greedier"])
        subprocess.run([LUAC, "-p", str(special)], check=True)
    print("PASS Python, Lua and bundled gameplay syntax")


if __name__ == "__main__":
    main()
