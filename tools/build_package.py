#!/usr/bin/env python3
"""Assemble a local, reproducible installer directory. Does not install/publish."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil

if __package__:
    from .game_profiles import DEFAULT_BACKEND, build_profile, source_profile
else:
    from game_profiles import DEFAULT_BACKEND, build_profile, source_profile


def game_profile(source, backend=DEFAULT_BACKEND):
    return source_profile(backend, root=source)


def build(build_directory, output):
    source = Path(__file__).resolve().parent.parent
    profile = build_profile(build_directory)
    output.mkdir(parents=True, exist_ok=False)
    files = {}
    for name in ("winmm.dll", "isaac_lan_probe.dll", "isaac_lan_check.exe"):
        contents = (build_directory / name).read_bytes()
        shutil.copy2(build_directory / name, output / name)
        files[name] = hashlib.sha256(contents).hexdigest()
    version = (source / "VERSION").read_text().strip()
    payload = {
        "format": 1,
        "game_build": profile["game_build"],
        "backend": profile["backend"],
        "extension_version": version,
        "files": files,
    }
    shutil.copy2(source / "package/install.py", output)
    (output / "game-profile.json").write_text(json.dumps(profile, indent=2) + "\n")
    payload["linux_files"] = {
        name: hashlib.sha256((output / name).read_bytes()).hexdigest()
        for name in ("install.py", "game-profile.json")
    }
    (output / "payload.json").write_text(json.dumps(payload, indent=2) + "\n")
    shutil.copy2(source / "package/install.ps1", output)
    shutil.copy2(source / "README.md", output)
    shutil.copy2(source / "docs/faq.md", output / "FAQ.md")
    for mode in ("Install", "Uninstall"):
        (output / f"{mode}.cmd").write_bytes(
            (
                '@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Mode '
                + mode
                + "\r\npause\r\n"
            ).encode("ascii")
        )
    shutil.copytree(source / "third_party", output / "licenses")
    return payload


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.build, args.output), indent=2))
