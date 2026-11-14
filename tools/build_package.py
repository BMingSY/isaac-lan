#!/usr/bin/env python3
"""Assemble a local, reproducible installer directory. Does not install/publish."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import re
import subprocess
from extension_package import LOADER_ABI


def game_profile(source):
    backend = source / "src/engine/versions/j460"
    header = (backend / "entrypoints.h").read_text()
    addresses = dict(re.findall(r"std::uint32_t (\w+) = (0x[0-9a-f]+);", header))
    declarations = (backend / "profile.h").read_text()
    profile = {
        "format": 1,
        "game_build": re.search(r'char version\[\] = "([^"]+)"', declarations)[1],
        "version_rva": int(re.search(r"versionRva = (0x[0-9a-f]+)", declarations)[1], 16),
        "minimum_image_size": int(
            re.search(r"minimumImageSize = (0x[0-9a-f]+)", declarations)[1], 16
        ),
        "sections": [
            dict(zip(("start", "size", "flags"), (int(value, 16) for value in values)))
            for values in re.findall(
                r"RequiredSection\{(0x[0-9a-f]+), (0x[0-9a-f]+), (0x[0-9a-f]+)\}", declarations
            )
        ],
        "signatures": [],
    }
    signatures = (backend / "signatures.inc").read_text()
    for entry, name, values, mask in re.findall(
        r'\{j460::entry::(\w+),\s*"([^"]+)",\s*\{([^}]+)\},\s*(0x[0-9a-f]+)\}', signatures
    ):
        data = bytes(int(value.strip(), 0) for value in values.split(","))
        assert len(data) == 16
        profile["signatures"].append(
            {
                "name": name,
                "rva": int(addresses[entry], 16),
                "bytes": data.hex(),
                "mask": int(mask, 16),
            }
        )
    assert len(profile["signatures"]) == len(re.findall(r"\{j460::entry::", signatures))
    assert len(profile["sections"]) == 3
    return profile


def build(build_directory, output, *, strip_binaries=False):
    source = Path(__file__).resolve().parent.parent
    strip_tool = None
    if strip_binaries:
        cache = (build_directory / "CMakeCache.txt").read_text()
        match = re.search(r"^CMAKE_STRIP:[^=\n]+=(.+)$", cache, re.MULTILINE)
        if not match or match[1].endswith("-NOTFOUND"):
            raise ValueError("The configured Windows toolchain must provide CMAKE_STRIP")
        strip_tool = match[1]
    output.mkdir(parents=True, exist_ok=False)
    files = {}
    for name in ("winmm.dll", "isaac_lan_probe.dll", "isaac_lan_check.exe"):
        destination = output / name
        shutil.copy2(build_directory / name, destination)
        if strip_tool:
            # Keep the original build and its symbols for diagnostics. Hash the
            # final payload so installers and Workshop use these exact bytes.
            subprocess.run([strip_tool, "--strip-all", str(destination)], check=True)
        files[name] = hashlib.sha256(destination.read_bytes()).hexdigest()
    version = (source / "VERSION").read_text().strip()
    payload = {
        "format": 1,
        "game_build": "1.9.7.17.J460",
        "extension_version": version,
        "loader_abi": LOADER_ABI,
        "files": files,
    }
    shutil.copy2(source / "package/install.py", output)
    (output / "game-profile.json").write_text(json.dumps(game_profile(source), indent=2) + "\n")
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
                '@echo off\r\nsetlocal\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Mode '
                + mode
                + '\r\nset "installer_exit=%errorlevel%"\r\npause\r\nexit /b %installer_exit%\r\n'
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
