#!/usr/bin/env python3
"""Export a runnable Mod example with the same SDK embedded in Isaac LAN."""

import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def export(destination):
    destination = Path(destination)
    if destination.exists():
        raise ValueError("Choose a new example directory")
    shutil.copytree(ROOT / "examples/mod-api", destination)
    shutil.copy2(ROOT / "src/bridge/api/sdk.lua", destination / "isaac_lan.lua")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    print(export(parser.parse_args().destination))


if __name__ == "__main__":
    main()
