#!/usr/bin/env python3
"""Assemble a local, reproducible installer directory. Does not install/publish."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

if __package__:
    from .extension_package import LOADER_ABI
    from .game_profiles import DEFAULT_BACKEND, RELEASE_BACKENDS, build_profile, source_profile
else:
    from extension_package import LOADER_ABI
    from game_profiles import DEFAULT_BACKEND, RELEASE_BACKENDS, build_profile, source_profile

ROOT = Path(__file__).resolve().parents[1]


def game_profile(source, backend=DEFAULT_BACKEND):
    return source_profile(backend, root=source)


def stage_binary(build_directory, name, destination, strip_binaries):
    shutil.copy2(build_directory / name, destination)
    if strip_binaries:
        cache = (build_directory / "CMakeCache.txt").read_text()
        match = re.search(r"^CMAKE_STRIP:[^=\n]+=(.+)$", cache, re.MULTILINE)
        if not match or match[1].endswith("-NOTFOUND"):
            raise ValueError("The configured Windows toolchain must provide CMAKE_STRIP")
        # PE stripping otherwise replaces the build timestamp with the current time.
        subprocess.run([match[1], "--strip-all", "--preserve-dates", str(destination)], check=True)
    return hashlib.sha256(destination.read_bytes()).hexdigest()


def write_payload(build_directory, output, profile, strip_binaries, shared_loader=None):
    files = {
        "winmm.dll": shared_loader
        or stage_binary(build_directory, "winmm.dll", output / "winmm.dll", strip_binaries)
    }
    for name in ("isaac_lan_probe.dll", "isaac_lan_check.exe"):
        files[name] = stage_binary(build_directory, name, output / name, strip_binaries)
    version = (ROOT / "VERSION").read_text().strip()
    payload = {
        "format": 1,
        "game_build": profile["game_build"],
        "backend": profile["backend"],
        "extension_version": version,
        "loader_abi": LOADER_ABI,
        "files": files,
    }
    (output / "game-profile.json").write_text(json.dumps(profile, indent=2) + "\n")
    payload["linux_files"] = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (ROOT / "package/install.py", output / "game-profile.json")
    }
    (output / "payload.json").write_text(json.dumps(payload, indent=2) + "\n")
    return payload


def write_installer(output):
    output.mkdir(parents=True, exist_ok=False)
    shutil.copy2(ROOT / "package/install.py", output)
    shutil.copy2(ROOT / "package/install.ps1", output)
    shutil.copy2(ROOT / "README.md", output)
    shutil.copy2(ROOT / "docs/faq.md", output / "FAQ.md")
    for mode in ("Install", "Uninstall"):
        (output / f"{mode}.cmd").write_bytes(
            (
                '@echo off\r\nsetlocal\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Mode '
                + mode
                + '\r\nset "installer_exit=%errorlevel%"\r\npause\r\nexit /b %installer_exit%\r\n'
            ).encode("ascii")
        )
    shutil.copytree(ROOT / "third_party", output / "licenses")


def build(build_directory, output, *, strip_binaries=False):
    profile = build_profile(build_directory)
    write_installer(output)
    return write_payload(build_directory, output, profile, strip_binaries)


def build_bundle(build_directories, output, *, strip_binaries=False):
    builds = {}
    for directory in build_directories:
        profile = build_profile(directory)
        backend = profile["backend"]
        if backend in builds:
            raise ValueError(f"Duplicate build for {backend}")
        builds[backend] = (directory, profile)
    if builds.keys() != set(RELEASE_BACKENDS):
        raise ValueError(f"Release requires builds for {', '.join(RELEASE_BACKENDS)}")
    write_installer(output)
    shared_loader = stage_binary(
        builds[DEFAULT_BACKEND][0], "winmm.dll", output / "winmm.dll", strip_binaries
    )
    for backend in RELEASE_BACKENDS:
        directory, profile = builds[backend]
        target = output / "backends" / backend
        target.mkdir(parents=True)
        write_payload(directory, target, profile, strip_binaries, shared_loader)
    index = {"format": 3, "backends": list(RELEASE_BACKENDS)}
    (output / "payload.json").write_text(json.dumps(index, indent=2) + "\n")
    return index


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if len(args.build) == 1:
        payload = build(args.build[0], args.output)
    else:
        payload = build_bundle(args.build, args.output)
    print(json.dumps(payload, indent=2))
