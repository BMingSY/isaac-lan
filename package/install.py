#!/usr/bin/env python3
"""Install the Windows extension for Linux Steam/Proton without starting the game."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile

OWNED = ("winmm.dll", "isaac_lan_probe.dll")


def regular(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Expected an ordinary file: {path}")
    return path


def digest(path):
    return hashlib.sha256(regular(path).read_bytes()).hexdigest()


def check_game(path, profile):
    data = regular(path).read_bytes()
    if len(data) < 64 or len(data) > 512 * 1024 * 1024 or data[:2] != b"MZ":
        raise ValueError("Expected a Windows Isaac executable")

    def read(fmt, offset):
        if offset < 0 or offset + struct.calcsize(fmt) > len(data):
            raise ValueError("Truncated PE header")
        return struct.unpack_from(fmt, data, offset)

    nt = read("<I", 60)[0]
    if nt < 64 or data[nt : nt + 4] != b"PE\0\0":
        raise ValueError("Invalid PE signature")
    machine, count, _, _, _, optional_size, flags = read("<HHIIIHH", nt + 4)
    optional = nt + 24
    image_size = read("<I", optional + 56)[0]
    if (
        machine != 0x14C
        or not flags & 2
        or flags & 0x2000
        or optional_size < 224
        or not 1 <= count <= 96
        or read("<H", optional)[0] != 0x10B
        or image_size < profile["minimum_image_size"]
    ):
        raise ValueError("Expected Windows Repentance+ J460, 32-bit x86")
    sections = []
    for i in range(count):
        _, virtual_size, rva, raw_size, raw, _, _, _, _, characteristics = read(
            "<8sIIIIIIHHI", optional + optional_size + i * 40
        )
        if raw + raw_size > len(data) or rva + max(raw_size, virtual_size) > image_size:
            raise ValueError("Invalid PE section")
        sections.append((rva, virtual_size, raw, raw_size, characteristics))
    for required in profile["sections"]:
        if not any(
            rva <= required["start"]
            and required["start"] + required["size"] <= rva + size
            and flags & required["flags"] == required["flags"]
            for rva, size, _, _, flags in sections
        ):
            raise ValueError("Unsupported game section layout")

    def at(rva, size):
        for start, _, raw, raw_size, _ in sections:
            offset = rva - start
            if offset >= 0 and offset + size <= raw_size:
                return data[raw + offset : raw + offset + size]
        raise ValueError("Required game address is not backed by a PE section")

    marker = profile["game_build"].encode("ascii") + b"-"
    if at(profile["version_rva"], len(marker)) != marker:
        raise ValueError("Unsupported game version; expected Repentance+ 1.9.7.17.J460")
    for signature in profile["signatures"]:
        expected = bytes.fromhex(signature["bytes"])
        actual = at(signature["rva"], len(expected))
        if any(
            actual[i] != expected[i] for i in range(len(expected)) if signature["mask"] & (1 << i)
        ):
            raise ValueError(f"Game code differs at {signature['name']}")


def game_running():
    for entry in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            args = entry.read_bytes().split(b"\0")
            if any(
                arg.replace(b"\\", b"/").rsplit(b"/", 1)[-1].lower() == b"isaac-ng.exe"
                for arg in args
            ):
                return True
        except OSError:
            continue
    return False


def install(package, game, mode="Install"):
    package, game = package.resolve(), game.resolve(strict=True)
    regular(game / "isaac-ng.exe")
    marker = game / ".isaac-lan-install"
    directory = game / "isaac-lan"
    record = directory / "installation.json"
    if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
        raise ValueError("The extension data directory must be an ordinary directory")
    installed = marker.exists() or marker.is_symlink()
    previous = None
    if installed:
        if regular(marker).read_text().strip() != "IsaacLAN/1":
            raise ValueError("Unrecognized installation marker")
        previous = json.loads(regular(record).read_text())
        if previous.get("format") != 1:
            raise ValueError("Unsupported installation record")
    elif record.exists() or record.is_symlink():
        raise ValueError("An installation record exists without its marker")
    payload = None
    if mode != "Uninstall":
        payload = json.loads(regular(package / "payload.json").read_text())
        if payload.get("format") != 1 or payload.get("game_build") != "1.9.7.17.J460":
            raise ValueError("Invalid package manifest")
        for name in (*OWNED, "isaac_lan_check.exe"):
            if digest(package / name) != payload["files"][name]:
                raise ValueError(f"Package file failed verification: {name}")
        for name in ("install.py", "game-profile.json"):
            if digest(package / name) != payload.get("linux_files", {}).get(name):
                raise ValueError(f"Package file failed verification: {name}")
        profile = json.loads(regular(package / "game-profile.json").read_text())
        if profile.get("format") != 1 or profile.get("game_build") != payload["game_build"]:
            raise ValueError("Invalid game profile")
        try:
            check_game(game / "isaac-ng.exe", profile)
        except (ValueError, struct.error) as error:
            if mode != "Status":
                raise
            return {"installed": installed, "gameCompatible": False, "detail": str(error)}
        if mode == "Status":
            return {
                "installed": installed,
                "gameCompatible": True,
                "gameBuild": profile["game_build"],
            }
    if game_running():
        raise ValueError("Close Isaac before installing or uninstalling")
    for name in OWNED:
        target = game / name
        if target.exists() or target.is_symlink():
            if not installed or digest(target) != previous.get("files", {}).get(name):
                raise ValueError(f"Existing {name} is not an unchanged Isaac LAN file")
        elif installed:
            raise ValueError(f"Installed file is missing: {name}")
    if mode == "Uninstall" and not installed:
        return {"installed": False}
    targets = [game / name for name in OWNED] + [record, marker]
    backups = {path: path.read_bytes() if path.exists() else None for path in targets}
    with tempfile.TemporaryDirectory(prefix=".isaac-lan-transaction-", dir=game) as staging:
        staging = Path(staging)
        if mode == "Install":
            for name in OWNED:
                shutil.copyfile(package / name, staging / name)
            (staging / "installation.json").write_text(json.dumps(payload, indent=2) + "\n")
            (staging / ".isaac-lan-install").write_text("IsaacLAN/1\n")
        touched = []
        try:
            if mode == "Install":
                directory.mkdir(exist_ok=True)
            for target in targets:
                touched.append(target)
                if mode == "Install":
                    os.replace(staging / target.name, target)
                else:
                    target.unlink()
        except BaseException:
            for index, target in enumerate(reversed(touched)):
                old = backups[target]
                if old is None:
                    target.unlink(missing_ok=True)
                else:
                    recovery = staging / f"rollback-{index}"
                    recovery.write_bytes(old)
                    os.replace(recovery, target)
            raise
    return {"installed": mode == "Install", "directory": str(game)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("Install", "Uninstall", "Status"), default="Install")
    parser.add_argument("--game-directory", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = install(Path(__file__).resolve().parent, args.game_directory, args.mode)
        print(json.dumps(result, ensure_ascii=False))
    except (ValueError, OSError, KeyError, struct.error) as error:
        parser.exit(1, f"Isaac LAN: {error}\n")


if __name__ == "__main__":
    main()
