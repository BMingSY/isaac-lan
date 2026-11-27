#!/usr/bin/env python3
"""Verify a release ZIP, manifest, x86 PE files and system DLL dependencies."""

import argparse
import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile

import pefile
from extension_package import LOADER_ABI
from game_profiles import (
    DEFAULT_BACKEND,
    LEGACY_BACKENDS,
    RELEASE_BACKENDS,
    bundle_backends,
    release_name,
    validate,
)


BINARIES = {"winmm.dll", "isaac_lan_probe.dll", "isaac_lan_check.exe"}
PAYLOAD_FILES = BINARIES | {"game-profile.json", "payload.json"}
STEAM_LOG_TOOLS = {"Collect-Steam-Logs.cmd", "collect_steam_logs.ps1"}
SHARED_FILES = STEAM_LOG_TOOLS | {
    "Install.cmd",
    "Uninstall.cmd",
    "install.ps1",
    "install.py",
    "README.md",
    "README.en.md",
    "LICENSE",
    "FAQ.md",
    "payload.json",
    "licenses/MinHook-LICENSE.txt",
    "licenses/imgui-LICENSE.txt",
    "licenses/miniz-LICENSE.txt",
    "licenses/zstd-LICENSE.txt",
    "licenses/ENet-LICENSE.txt",
    "licenses/GameNetworkingSockets-LICENSE.txt",
}
LEGACY_FILES = SHARED_FILES | PAYLOAD_FILES


def bundle_files(backends):
    return (
        SHARED_FILES
        | {"winmm.dll"}
        | {
            f"backends/{backend}/{name}"
            for backend in backends
            for name in PAYLOAD_FILES - {"winmm.dll"}
        }
    )


FILES = bundle_files(RELEASE_BACKENDS)
SYSTEM_DLLS = {
    "bcrypt.dll",
    "dwmapi.dll",
    "gdi32.dll",
    "gdiplus.dll",
    "imm32.dll",
    "iphlpapi.dll",
    "kernel32.dll",
    "msvcrt.dll",
    "opengl32.dll",
    "shell32.dll",
    "user32.dll",
    "ws2_32.dll",
    "winmm.dll",
    "advapi32.dll",
    "ole32.dll",
    "oleaut32.dll",
    "psapi.dll",
    "comdlg32.dll",
    "winhttp.dll",
}


def check_payload(zipped, root, prefix, backend, tag, require_stripped, bundled):
    payload = json.loads(zipped.read(prefix + "payload.json"))
    if (
        payload.get("format") != 1
        or payload.get("backend") != backend
        or not payload.get("game_build")
        or payload.get("extension_version") != tag[1:]
        or (
            (bundled or "loader_abi" in payload)
            and (type(payload.get("loader_abi")) is not int or payload["loader_abi"] != LOADER_ABI)
        )
        or set(payload["files"]) != BINARIES
    ):
        raise ValueError("Release manifest differs")
    profile = validate(json.loads(zipped.read(prefix + "game-profile.json")))
    if profile["game_build"] != payload["game_build"] or profile["backend"] != payload.get(
        "backend"
    ):
        raise ValueError("Release game profile differs from manifest")
    for name in BINARIES:
        if (
            hashlib.sha256(
                zipped.read((root if name == "winmm.dll" else prefix) + name)
            ).hexdigest()
            != payload["files"][name]
        ):
            raise ValueError(f"Package file hash differs: {name}")
    if set(payload.get("linux_files", {})) != {"install.py", "game-profile.json"}:
        raise ValueError("Linux installer manifest differs")
    for name, expected in payload["linux_files"].items():
        file_prefix = root if name == "install.py" else prefix
        if hashlib.sha256(zipped.read(file_prefix + name)).hexdigest() != expected:
            raise ValueError(f"Package file hash differs: {name}")
    imports = {}
    for name in sorted(BINARIES):
        contents = zipped.read((root if name == "winmm.dll" else prefix) + name)
        pe = pefile.PE(data=contents, fast_load=True)
        try:
            if pe.FILE_HEADER.Machine != 0x14C or pe.OPTIONAL_HEADER.Magic != 0x10B:
                raise ValueError(f"Expected a 32-bit x86 PE file: {name}")
            is_dll = bool(pe.FILE_HEADER.Characteristics & 0x2000)
            if is_dll != name.endswith(".dll"):
                raise ValueError(f"Unexpected PE file kind: {name}")
            # A stripped PE can retain a COFF string table for long section
            # names such as .eh_frame, without retaining any symbols.
            if require_stripped and (
                pe.FILE_HEADER.NumberOfSymbols
                or any(section.Name.startswith((b".debug", b".zdebug")) for section in pe.sections)
            ):
                raise ValueError(f"Release binary retains debug information: {name}")
            pe.parse_data_directories(
                directories=[
                    pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"],
                    pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXPORT"],
                ]
            )
            required = sorted(
                entry.dll.decode("ascii").lower() for entry in pe.DIRECTORY_ENTRY_IMPORT
            )
            if any(dll not in SYSTEM_DLLS for dll in required):
                raise ValueError(f"Unexpected runtime DLL dependency: {name}: {required}")
            if name == "isaac_lan_probe.dll":
                exports = {symbol.name for symbol in pe.DIRECTORY_ENTRY_EXPORT.symbols}
                if b"IsaacLanBootstrap" not in exports:
                    raise ValueError("Native bootstrap export is missing")
                if "loader_abi" in payload and b"IsaacLanLoaderABI" not in exports:
                    raise ValueError("Native loader ABI export is missing")
            imports[name] = required
        finally:
            pe.close()
    return imports


def check(archive, tag, *, require_stripped=False, allow_legacy=False):
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Expected a version tag such as v0.1.0")
    standard = release_name(tag) + ".zip"
    legacy_names = {
        standard: DEFAULT_BACKEND,
        f"Isaac-LAN-{tag}-j835-windows-x86.zip": "repentance",
    }
    if archive.name != standard and not (allow_legacy and archive.name in legacy_names):
        raise ValueError("Unexpected release archive name")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_suffix(".zip.sha256")
    if checksum.read_text(encoding="ascii").strip() != f"{digest}  {archive.name}":
        raise ValueError("Release archive checksum differs")
    root = archive.stem + "/"
    with ZipFile(archive) as zipped:
        names = zipped.namelist()
        if root + "payload.json" not in names:
            raise ValueError("Release archive contains missing or unexpected files")
        index = json.loads(zipped.read(root + "payload.json"))
        legacy = allow_legacy and index.get("format") == 1
        if legacy:
            backend = index.get("backend")
            if (
                not isinstance(backend, str)
                or LEGACY_BACKENDS.get(backend, backend) != legacy_names[archive.name]
            ):
                raise ValueError("Historical release backend differs from archive name")
            expected, directories = LEGACY_FILES, {backend: root}
        else:
            if archive.name != standard:
                raise ValueError("Unexpected release archive name for a bundle")
            backends = bundle_backends(index, allow_legacy=allow_legacy)
            expected = bundle_files(backends)
            directories = {b: root + f"backends/{b}/" for b in backends}
        if allow_legacy and not any(root + name in names for name in STEAM_LOG_TOOLS):
            expected = expected - STEAM_LOG_TOOLS
        if allow_legacy and root + "LICENSE" not in names:
            # Published installers predating the project license had only the Chinese README.
            expected = expected - {"LICENSE", "README.en.md"}
        if len(names) != len(expected) or set(names) != {root + name for name in expected}:
            raise ValueError("Release archive contains missing or unexpected files")
        if zipped.testzip() is not None:
            raise ValueError("Release archive is damaged")
        imports = {
            backend: check_payload(zipped, root, prefix, backend, tag, require_stripped, not legacy)
            for backend, prefix in directories.items()
        }
        if "files" in index and not legacy:
            uninstall_files = {
                "winmm.dll": hashlib.sha256(zipped.read(root + "winmm.dll")).hexdigest()
            }
            for backend, directory in directories.items():
                name = f"isaac-lan/backends/{backend}/isaac_lan_probe.dll"
                uninstall_files[name] = hashlib.sha256(
                    zipped.read(directory + "isaac_lan_probe.dll")
                ).hexdigest()
            if index["files"] != uninstall_files:
                raise ValueError("Uninstall file hashes differ from the release")
        launchers = {"Install.cmd": b"install.ps1", "Uninstall.cmd": b"install.ps1"}
        if "Collect-Steam-Logs.cmd" in expected:
            launchers["Collect-Steam-Logs.cmd"] = b"collect_steam_logs.ps1"
        for name, script in launchers.items():
            contents = zipped.read(root + name)
            if b"\r\n" not in contents or script not in contents:
                raise ValueError(f"Invalid Windows installer entry: {name}")
    return {"archive": str(archive), "tag": tag, "sha256": digest, "imports": imports}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--require-stripped", action="store_true")
    parser.add_argument(
        "--allow-legacy", action="store_true", help="Also accept historical release layouts"
    )
    args = parser.parse_args()
    print(
        json.dumps(
            check(
                args.archive,
                args.tag,
                require_stripped=args.require_stripped,
                allow_legacy=args.allow_legacy,
            ),
            indent=2,
        )
    )
