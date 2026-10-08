#!/usr/bin/env python3
"""Format project C++, Lua, Python and CMake files; --check makes no edits."""

import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    tracked = (
        subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
        )
        .decode()
        .split("\0")
    )
    files = sorted(set(path for path in tracked if path))
    groups = [
        (
            ["clang-format", "--dry-run", "--Werror"] if args.check else ["clang-format", "-i"],
            [p for p in files if p.endswith((".cpp", ".h", ".inc", ".h.in"))],
        ),
        (
            ["stylua", "--verify", *(["--check"] if args.check else [])],
            [p for p in files if p.endswith(".lua")],
        ),
        (
            ["ruff", "format", *(["--check"] if args.check else [])],
            [p for p in files if p.endswith(".py")],
        ),
        (
            [
                "cmake-format",
                "--config-files",
                ".cmake-format.json",
                "--check" if args.check else "-i",
            ],
            [p for p in files if p == "CMakeLists.txt" or p.endswith(".cmake")],
        ),
    ]
    failed = False
    for command, paths in groups:
        if paths:
            print(f"{command[0]}: {len(paths)} files", flush=True)
            result = subprocess.run([*command, *paths], cwd=ROOT, check=False)
            failed |= result.returncode != 0
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
