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
EDITIONS = ("repentance", "repentance_plus")
HINTS = {
    "GAME_PATH": "Select the game folder containing isaac-ng.exe (Steam > Manage > Browse local files).",
    "PACKAGE_INVALID": "Extract the entire release ZIP into a new folder and retry. Check security-software quarantine if a file is missing.",
    "GAME_INCOMPATIBLE": "Use the Windows game version specified in this package manifest. In Steam, check the game version and verify installed files; Linux/Steam Deck must use Proton.",
    "GAME_RUNNING": "Close Isaac, wait for it to exit, then retry. Do not replace DLLs while the game is running.",
    "INSTALLATION_INVALID": "Check the named installation path. Use an extracted Isaac LAN package to repair missing installation records.",
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
        value = json.loads(regular(path).read_text(encoding="utf-8-sig"))
        if not isinstance(value, dict):
            raise ValueError("Expected a JSON object")
        return value
    except (ValueError, FileNotFoundError) as error:
        raise InstallerError(code, f"Cannot read {path}: {error}") from error


def check_manifest(value, names, code, field="files", expected_format=1):
    hashes = value.get(field)
    if (
        type(value.get("format")) is not int
        or value["format"] != expected_format
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


def check_game(data, profile):
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
        raise ValueError("Expected a supported Windows Isaac build, 32-bit x86")
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
        raise ValueError(f"Unsupported game version; expected {profile['game_build']}")
    for signature in profile["signatures"]:
        expected = bytes.fromhex(signature["bytes"])
        actual = at(signature["rva"], len(expected))
        if any(
            actual[i] != expected[i] for i in range(len(expected)) if signature["mask"] & (1 << i)
        ):
            raise ValueError(f"Game code differs at {signature['name']}")


def game_running(game, processes=Path("/proc")):
    executable = game / "isaac-ng.exe"
    for entry in processes.glob("[0-9]*/cmdline"):
        try:
            args = [os.fsdecode(v).replace("\\", "/") for v in entry.read_bytes().split(b"\0") if v]
            if not args:
                continue
            program = args[0].rsplit("/", 1)[-1].lower()
            if program in ("wine", "wine64", "wine-preloader", "wine64-preloader"):
                args = args[1:2]
            elif program == "isaac-ng.exe":
                args = args[:1]
            else:
                continue
            if not args or args[0].rsplit("/", 1)[-1].lower() != "isaac-ng.exe":
                continue
            path = args[0]
            if path[:3].lower() == "z:/":
                path = path[2:]
            if path.startswith("/"):
                if Path(path).resolve() == executable:
                    return True
            elif (entry.parent / "cwd").resolve() == game:
                return True
            else:
                # Proton drive letters can differ from the host library path.
                # The loaded PE mapping identifies the selected installation.
                with (entry.parent / "maps").open(errors="replace") as maps:
                    if any(line.rstrip().endswith(" " + str(executable)) for line in maps):
                        return True
        except OSError:
            continue
    return False


def backend_file(backend):
    return f"isaac-lan/backends/{backend}/isaac_lan_probe.dll"


def installed_backend(name):
    # Old installation records used the executable's build number as the directory.
    return name in EDITIONS or re.fullmatch(r"j[0-9]+", name) is not None


def owned_hashes(record):
    names = OWNED
    if record.get("format") == 2:
        backends = record.get("backends")
        if (
            not isinstance(backends, dict)
            or not backends
            or not all(
                installed_backend(b) and isinstance(v, str) and v for b, v in backends.items()
            )
        ):
            raise InstallerError("INSTALLATION_INVALID", "Invalid installed backend list")
        names = ["winmm.dll", *(backend_file(b) for b in backends)]
        check_manifest(record, names, "INSTALLATION_INVALID", expected_format=2)
        if set(record["files"]) != set(names):
            raise InstallerError("INSTALLATION_INVALID", "Unexpected installed file")
    else:
        check_manifest(record, names, "INSTALLATION_INVALID")
    return {name: record["files"][name] for name in names}


def payloads(package):
    index = read_json(package / "payload.json", "PACKAGE_INVALID")
    if index.get("format") != 3:
        yield package, index, None
        return
    backends = index.get("backends")
    if (
        not isinstance(backends, list)
        or not all(isinstance(b, str) for b in backends)
        or sorted(backends) != list(EDITIONS)
    ):
        raise InstallerError("PACKAGE_INVALID", "Invalid package backend list")
    parent = package / "backends"
    for backend in backends:
        directory = parent / backend
        if parent.is_symlink() or directory.is_symlink() or not directory.is_dir():
            raise InstallerError("PACKAGE_INVALID", f"Expected an ordinary directory: {directory}")
        yield directory, read_json(directory / "payload.json", "PACKAGE_INVALID"), backend


def select_payload(package, executable):
    image = regular(executable).read_bytes() if executable is not None else None
    matched_build = None
    record = None
    sources = {}
    details = []
    for directory, payload, backend in payloads(package):
        files = [("files", OWNED)]
        if image is not None:
            files.append(("linux_files", ("install.py", "game-profile.json")))
        for field, names in files:
            check_manifest(payload, names, "PACKAGE_INVALID", field)
            for name in names:
                path = (package if name in ("install.py", "winmm.dll") else directory) / name
                try:
                    if digest(path) != payload[field][name]:
                        raise ValueError(f"Package file failed verification: {name}")
                except (ValueError, FileNotFoundError) as error:
                    raise InstallerError("PACKAGE_INVALID", f"{path}: {error}") from error
        if (
            not isinstance(payload.get("game_build"), str)
            or not payload["game_build"]
            or (backend is not None and payload.get("backend") != backend)
        ):
            raise InstallerError("PACKAGE_INVALID", "Invalid game build in payload")
        if backend is None:
            record = payload
            sources = {name: directory / name for name in OWNED}
        else:
            if (
                not isinstance(payload.get("extension_version"), str)
                or not payload["extension_version"]
                or type(payload.get("loader_abi")) is not int
            ):
                raise InstallerError("PACKAGE_INVALID", "Invalid extension version or loader ABI")
            if record is None:
                record = {
                    "format": 2,
                    "extension_version": payload["extension_version"],
                    "loader_abi": payload["loader_abi"],
                    "backends": {},
                    "files": {"winmm.dll": payload["files"]["winmm.dll"]},
                }
                sources["winmm.dll"] = package / "winmm.dll"
            if (record["extension_version"], record["loader_abi"]) != (
                payload["extension_version"],
                payload["loader_abi"],
            ):
                raise InstallerError(
                    "PACKAGE_INVALID", "Backend extension versions or loader ABIs differ"
                )
            name = backend_file(backend)
            record["backends"][backend] = payload["game_build"]
            record["files"][name] = payload["files"]["isaac_lan_probe.dll"]
            sources[name] = directory / "isaac_lan_probe.dll"
        if image is None:
            continue
        profile = read_json(directory / "game-profile.json", "PACKAGE_INVALID")
        if (
            profile.get("format") != 1
            or profile.get("game_build") != payload["game_build"]
            or profile.get("backend") != payload.get("backend")
        ):
            raise InstallerError("PACKAGE_INVALID", "Invalid game profile")
        try:
            check_game(image, profile)
        except (ValueError, struct.error) as error:
            details.append(f"{profile['game_build']}: {error}")
            continue
        except (KeyError, TypeError, AttributeError) as error:
            raise InstallerError("PACKAGE_INVALID", f"Invalid game profile: {error}") from error
        if matched_build is not None:
            raise InstallerError("PACKAGE_INVALID", "Multiple game backends match this executable")
        matched_build = profile["game_build"]
    if image is not None and matched_build is None:
        raise InstallerError("GAME_INCOMPATIBLE", "\n".join(details))
    return matched_build, record, sources


def install(package, game, mode="Install"):
    if mode not in ("Install", "Uninstall", "Status"):
        raise ValueError(f"Unknown installation mode: {mode}")
    package = package.resolve()
    try:
        game = game.resolve(strict=True)
        if game.is_file() and game.name.lower() == "isaac-ng.exe":
            game = game.parent
        if not game.is_dir():
            raise ValueError("Expected the game directory")
        if mode != "Uninstall":
            regular(game / "isaac-ng.exe")
    except (ValueError, FileNotFoundError, NotADirectoryError) as error:
        raise InstallerError("GAME_PATH", f"Invalid game directory {game}: {error}") from error
    if os.name != "posix":
        return install_files(package, game, mode)
    import fcntl

    # Hold the directory itself so the lock survives replacement of the record
    # and is released by the OS if an installer exits unexpectedly.
    lock = os.open(game, os.O_RDONLY | os.O_DIRECTORY)
    try:
        try:
            operation = fcntl.LOCK_SH if mode == "Status" else fcntl.LOCK_EX
            fcntl.flock(lock, operation | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise InstallerError(
                "FILE_IN_USE", "Another installer is using this game directory"
            ) from error
        return install_files(package, game, mode)
    finally:
        os.close(lock)


def remove_empty_directories(paths):
    for path in sorted(paths, key=lambda p: -len(p.parts)):
        try:
            path.rmdir()
        except FileNotFoundError:
            pass
        except OSError as error:
            if error.errno not in (errno.ENOTEMPTY, errno.EEXIST):
                print(
                    f"Isaac LAN: Could not remove empty directory {path}: {error}", file=sys.stderr
                )


def install_files(package, game, mode):
    marker = game / ".isaac-lan-install"
    directory = game / "isaac-lan"
    record = directory / "installation.json"
    if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
        raise InstallerError("INSTALLATION_INVALID", f"Expected an ordinary directory: {directory}")
    has_marker = marker.exists() or marker.is_symlink()
    has_record = record.exists() or record.is_symlink()
    installed = has_marker or has_record
    if mode == "Uninstall" and not installed:
        candidates = (game / "winmm.dll", game / "isaac_lan_probe.dll", directory / "backends")
        if not any(path.exists() or path.is_symlink() for path in candidates):
            return {"installed": False}
    previous = {}
    previous_record = None
    backup_metadata = False
    for present, path in ((has_marker, marker), (has_record, record)):
        if present and (path.is_symlink() or not path.is_file()):
            raise InstallerError("INSTALLATION_INVALID", f"Expected an ordinary file: {path}")
    valid_marker = (
        has_marker
        and marker.read_text(encoding="utf-8-sig", errors="replace").strip() == "IsaacLAN/1"
    )
    if has_record:
        try:
            previous_record = read_json(record, "INSTALLATION_INVALID")
            previous = owned_hashes(previous_record)
        except InstallerError:
            if not valid_marker:
                raise
            backup_metadata = True
    if has_marker and not valid_marker:
        if not previous:
            raise InstallerError(
                "INSTALLATION_INVALID", f"Unrecognized installation marker: {marker}"
            )
        backup_metadata = True
    payload = None
    sources = {}
    if mode != "Uninstall" or (not previous and (package / "payload.json").is_file()):
        try:
            executable = None if mode == "Uninstall" else game / "isaac-ng.exe"
            matched_build, payload, sources = select_payload(package, executable)
        except InstallerError as error:
            if mode != "Status" or error.code != "GAME_INCOMPATIBLE":
                raise
            return {
                "installed": installed,
                "gameCompatible": False,
                "detail": str(error),
                "nextStep": HINTS[error.code],
            }
        if mode == "Status":
            return {
                "installed": installed,
                "gameCompatible": True,
                "gameBuild": matched_build,
            }
    package_hashes = payload["files"] if payload else {}
    # A valid record survives a missing marker. With no record, a byte-for-byte
    # match against the verified package also identifies a manual installation.
    names = list(dict.fromkeys((*sources, *previous)))
    if mode == "Uninstall" and not previous:
        backends = directory / "backends"
        candidates = list(OWNED)
        if not backends.is_symlink() and backends.is_dir():
            candidates.extend(
                backend_file(p.name) for p in backends.iterdir() if installed_backend(p.name)
            )
        names = list(dict.fromkeys((*names, *candidates)))
    current = mode == "Install" and valid_marker and bool(previous) and previous_record == payload
    parents = {directory: mode == "Install"}
    targets = {}
    preserved = []
    backup_modified = backup_metadata
    for name in names:
        target = game / name
        unsafe = False
        ancestors = target.relative_to(game).parents
        for relative in reversed(ancestors):
            if relative == Path("."):
                continue
            parent = game / relative
            if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
                if mode == "Install":
                    raise InstallerError(
                        "FILE_CONFLICT", f"Expected an ordinary directory: {parent}"
                    )
                unsafe = True
                break
            parents[parent] = parents.get(parent, False) or (mode == "Install" and name in sources)
        if unsafe or target.is_symlink() or (target.exists() and not target.is_file()):
            if mode == "Uninstall":
                preserved.append(name)
                continue
            raise InstallerError("FILE_CONFLICT", f"Expected an ordinary file: {target}")
        if target.is_file():
            existing = digest(target)
            current = current and existing == package_hashes.get(name)
            if existing not in (previous.get(name), package_hashes.get(name)):
                if mode == "Uninstall" or name not in sources:
                    preserved.append(name)
                    continue
                if not installed or name == "winmm.dll":
                    raise InstallerError("FILE_CONFLICT", f"Another file uses {target}")
                backup_modified = True
        elif mode == "Uninstall":
            continue
        else:
            current = False
        targets[target] = name.replace("/", "_")
    if mode == "Uninstall" and not installed and not targets:
        return {"installed": False, "preservedFiles": preserved}
    if current:
        return {"installed": True, "directory": str(game)}
    if game_running(game):
        raise InstallerError("GAME_RUNNING", "This Isaac installation is still running")
    targets.update({record: record.name, marker: marker.name})
    staging = Path(tempfile.mkdtemp(prefix=".isaac-lan-transaction-", dir=game))
    preserve_recovery = False
    try:
        backups = {}
        for target, staged_name in targets.items():
            backup = staging / f"old-{staged_name}" if target.exists() else None
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
            for name, source in sources.items():
                staged = staging / targets[game / name]
                shutil.copyfile(source, staged)
                if digest(staged) != payload["files"][name]:
                    raise InstallerError(
                        "PACKAGE_INVALID", f"Package file changed while staging: {name}"
                    )
            (staging / "installation.json").write_text(
                json.dumps(payload, indent=2) + "\n", encoding="utf-8"
            )
            (staging / ".isaac-lan-install").write_text("IsaacLAN/1\n", encoding="utf-8")
        touched = []
        created = []
        try:
            if mode == "Install":
                for parent in sorted(
                    (p for p in parents if parents[p]), key=lambda path: len(path.parts)
                ):
                    if not parent.exists():
                        parent.mkdir()
                        created.append(parent)
            for target, staged_name in targets.items():
                touched.append(target)
                staged = staging / staged_name
                if staged.exists():
                    os.replace(staged, target)
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
            remove_empty_directories(created)
            if failures:
                raise InstallerError(
                    "ROLLBACK_FAILED",
                    f"Operation failed: {original}\nRecovery folder: {staging}\n"
                    + "\n".join(failures),
                ) from original
            preserve_recovery = False
            raise
        preserve_recovery = backup_modified
    finally:
        if not preserve_recovery:
            try:
                shutil.rmtree(staging)
            except OSError as error:
                print(
                    f"Isaac LAN: Could not remove temporary folder {staging}: {error}",
                    file=sys.stderr,
                )
    remove_empty_directories(parents.keys() - {directory})
    result = {"installed": mode == "Install", "directory": str(game), "preservedFiles": preserved}
    if backup_modified:
        result["backupDirectory"] = str(staging)
    return result


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
