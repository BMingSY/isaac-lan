#!/usr/bin/env python3
"""Discover, plan or explicitly run native suites using their existing options."""

import argparse
import json

from testing.discovery import ROOT, inventory, suite_command
from testing.engine import configure_interrupts, run_engine


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("list", help="Discover native runners and Lua fixtures by filename")
    catalog = inventory()
    for name in ("plan", "run"):
        command = commands.add_parser(name)
        command.add_argument("suite", choices=[entry["id"] for entry in catalog["suites"]])
        command.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == "list":
        print(json.dumps(catalog, ensure_ascii=False, indent=2))
        return 0
    arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    command = suite_command(args.suite, arguments)
    if args.action == "plan":
        suite = next(entry for entry in catalog["suites"] if entry["id"] == args.suite)
        print(
            json.dumps(
                {"suite": suite, "command": command, "game_started": False},
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    configure_interrupts()
    return run_engine(command, cwd=ROOT).returncode


if __name__ == "__main__":
    raise SystemExit(main())
