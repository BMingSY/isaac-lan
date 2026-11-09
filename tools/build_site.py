#!/usr/bin/env python3
"""Stage the static homepage and shared cover in dist/site for GitHub Pages."""

from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "dist" / "site"


def main():
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    shutil.copytree(ROOT / "site", OUTPUT)
    shutil.copyfile(
        ROOT / "docs" / "assets" / "steam-workshop-cover.png",
        OUTPUT / "assets" / "cover.png",
    )
    print("Static homepage ready: dist/site")


if __name__ == "__main__":
    main()
