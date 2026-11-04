#!/usr/bin/env python3
"""Install the Windows extension for Linux Steam/Proton without starting the game."""

import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import tempfile

OWNED = ("winmm.dll", "isaac_lan_probe.dll")
EXPECTED_BUILD = "1.9.7.17.J460"
HINTS = {
    "GAME_PATH": "Select the game folder containing isaac-ng.exe (Steam > Manage > Browse local files).",
    "PACKAGE_INVALID": "Extract the entire release ZIP into a new folder and retry. Check security-software quarantine if a file is missing.",
    "GAME_INCOMPATIBLE": f"Use Windows Repentance+ {EXPECTED_BUILD}. In Steam, check the game version and verify installed files; Linux/Steam Deck must use Proton.",
    "GAME_RUNNING": "Close Isaac, wait for it to exit, then retry. Do not replace DLLs while the game is running.",
    "INSTALLATION_INVALID": "Restore .isaac-lan-install and isaac-lan/installation.json from the same installation backup. Keep session data and logs; do not delete them to bypass this check.",
    "FILE_CONFLICT": "Back up the named file and identify its owner. Uninstall another extension with its own installer, or restore the matching Isaac LAN file from your backup, then retry.",
    "PERMISSION_DENIED": "Check write permissions and security-software blocks for the named path. On Windows, retry as administrator only if this folder requires it; on Linux, use the Steam library owner's account.",
    "FILE_IN_USE": "Close Isaac and any program using the named file, then retry.",
    "DISK_FULL": "Free space on the game drive, then retry.",
    "IO_ERROR": "Check the named path, available disk space and drive access, then retry. Keep the full error if it persists.",
    "ROLLBACK_FAILED": "Do not start the game yet. Keep the recovery folder; use recovery.json to restore the listed backups to their original paths, then retry.",
}


class InstallerError(ValueError):
    def __init__(self, code, detail):
        self.code = code
        super().__init__(detail)


def error_message(error):
    code = getattr(error, "code", "IO_ERROR")
    if isinstance(error, PermissionError):
        code = "PERMISSION_DENIED"
    elif isinstance(error, OSError):
        if error.errno == errno.ENOSPC:
            code = "DISK_FULL"
        elif error.errno in (errno.EBUSY, errno.ETXTBSY):
            code = "FILE_IN_USE"
    return f"Isaac LAN [{code}]: {error}\nNext step: {HINTS[code]}"


def read_json(path, code):
    try:
        value = json.loads(regular(path).read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("Expected a JSON object")
        return value
    except (ValueError, FileNotFoundError) as error:
        raise InstallerError(code, f"Cannot read {path}: {error}") from error


def check_manifest(value, names, code, field="files"):
    hashes = value.get(field)
    if (
        type(value.get("format")) is not int
        or value["format"] != 1
        or not isinstance(hashes, dict)
        or any(
            not isinstance(hashes.get(name), str) or not re.fullmatch(r"[0-9a-f]{64}", hashes[name])
            for name in names
        )
    ):
        raise InstallerError(code, f"Invalid manifest format or {field} SHA-256 entries")


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
    if mode not in ("Install", "Uninstall", "Status"):
        raise ValueError(f"Unknown installation mode: {mode}")
    package = package.resolve()
    try:
        game = game.resolve(strict=True)
        regular(game / "isaac-ng.exe")
    except (ValueError, FileNotFoundError, NotADirectoryError) as error:
        raise InstallerError("GAME_PATH", f"Invalid game directory {game}: {error}") from error
    marker = game / ".isaac-lan-install"
    directory = game / "isaac-lan"
    record = directory / "installation.json"
    if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
        raise InstallerError("INSTALLATION_INVALID", f"Expected an ordinary directory: {directory}")
    installed = marker.exists() or marker.is_symlink()
    previous = None
    if installed:
        try:
            if regular(marker).read_text(encoding="utf-8").strip() != "IsaacLAN/1":
                raise ValueError("Unrecognized installation marker")
        except ValueError as error:
            raise InstallerError("INSTALLATION_INVALID", f"{marker}: {error}") from error
        previous = read_json(record, "INSTALLATION_INVALID")
        check_manifest(previous, OWNED, "INSTALLATION_INVALID")
    elif record.exists() or record.is_symlink():
        raise InstallerError(
            "INSTALLATION_INVALID", f"Installation record exists without its marker: {record}"
        )
    payload = None
    if mode != "Uninstall":
        payload = read_json(package / "payload.json", "PACKAGE_INVALID")
        check_manifest(payload, (*OWNED, "isaac_lan_check.exe"), "PACKAGE_INVALID")
        check_manifest(
            payload, ("install.py", "game-profile.json"), "PACKAGE_INVALID", "linux_files"
        )
        if payload.get("game_build") != EXPECTED_BUILD:
            raise InstallerError("PACKAGE_INVALID", "Invalid package game_build")
        for field, names in (
            ("files", (*OWNED, "isaac_lan_check.exe")),
            ("linux_files", ("install.py", "game-profile.json")),
        ):
            for name in names:
                try:
                    if digest(package / name) != payload[field][name]:
                        raise ValueError(f"Package file failed verification: {name}")
                except (ValueError, FileNotFoundError) as error:
                    raise InstallerError("PACKAGE_INVALID", f"{package / name}: {error}") from error
        profile = read_json(package / "game-profile.json", "PACKAGE_INVALID")
        if profile.get("format") != 1 or profile.get("game_build") != payload["game_build"]:
            raise InstallerError("PACKAGE_INVALID", "Invalid game profile")
        try:
            check_game(game / "isaac-ng.exe", profile)
        except (ValueError, struct.error) as error:
            if mode != "Status":
                raise InstallerError("GAME_INCOMPATIBLE", str(error)) from error
            return {
                "installed": installed,
                "gameCompatible": False,
                "detail": str(error),
                "nextStep": HINTS["GAME_INCOMPATIBLE"],
            }
        except (KeyError, TypeError, AttributeError) as error:
            raise InstallerError("PACKAGE_INVALID", f"Invalid game profile: {error}") from error
        if mode == "Status":
            return {
                "installed": installed,
                "gameCompatible": True,
                "gameBuild": profile["game_build"],
            }
    if game_running():
        raise InstallerError("GAME_RUNNING", "Isaac is still running")
    for name in OWNED:
        target = game / name
        if target.exists() or target.is_symlink():
            try:
                if not installed or digest(target) != previous["files"][name]:
                    raise ValueError(f"Existing {name} is not an unchanged Isaac LAN file")
            except ValueError as error:
                raise InstallerError("FILE_CONFLICT", f"{target}: {error}") from error
    if mode == "Uninstall" and not installed:
        return {"installed": False}
    targets = [game / name for name in OWNED] + [record, marker]
    staging = Path(tempfile.mkdtemp(prefix=".isaac-lan-transaction-", dir=game))
    preserve_recovery = False
    try:
        backups = {}
        for target in targets:
            backup = staging / f"old-{target.name}" if target.exists() else None
            if backup is not None:
                shutil.copyfile(target, backup)
            backups[target] = backup
        (staging / "recovery.json").write_text(
            json.dumps(
                {
                    "directory": str(game),
                    "files": [
                        {"path": str(path), "backup": backup.name if backup else None}
                        for path, backup in backups.items()
                    ],
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        if mode == "Install":
            for name in OWNED:
                shutil.copyfile(package / name, staging / name)
            (staging / "installation.json").write_text(
                json.dumps(payload, indent=2) + "\n", encoding="utf-8"
            )
            (staging / ".isaac-lan-install").write_text("IsaacLAN/1\n", encoding="utf-8")
        touched = []
        try:
            if mode == "Install":
                directory.mkdir(exist_ok=True)
            for target in targets:
                touched.append(target)
                if mode == "Install":
                    os.replace(staging / target.name, target)
                else:
                    target.unlink(missing_ok=True)
        except BaseException as original:
            preserve_recovery = True
            failures = []
            for index, target in enumerate(reversed(touched)):
                try:
                    backup = backups[target]
                    if backup is None:
                        target.unlink(missing_ok=True)
                    else:
                        if (
                            target.is_file()
                            and not target.is_symlink()
                            and digest(target) == digest(backup)
                        ):
                            continue
                        recovery = staging / f"rollback-{index}"
                        shutil.copyfile(backup, recovery)
                        os.replace(recovery, target)
                except OSError as error:
                    failures.append(f"{target}: {error}")
            if failures:
                raise InstallerError(
                    "ROLLBACK_FAILED",
                    f"Operation failed: {original}\nRecovery folder: {staging}\n"
                    + "\n".join(failures),
                ) from original
            preserve_recovery = False
            raise
    finally:
        if not preserve_recovery:
            try:
                shutil.rmtree(staging)
            except OSError as error:
                print(
                    f"Isaac LAN: Could not remove temporary folder {staging}: {error}",
                    file=sys.stderr,
                )
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
        parser.exit(1, error_message(error) + "\n")


if __name__ == "__main__":
    main()
