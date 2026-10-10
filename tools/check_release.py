#!/usr/bin/env python3
"""Verify a release ZIP, manifest, x86 PE files and system DLL dependencies."""

import argparse
import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile

import pefile


BINARIES = {"winmm.dll", "isaac_lan_probe.dll", "isaac_lan_check.exe"}
FILES = BINARIES | {
    "Install.cmd",
    "Uninstall.cmd",
    "install.ps1",
    "README.md",
    "payload.json",
    "licenses/MinHook-LICENSE.txt",
    "licenses/imgui-LICENSE.txt",
}
SYSTEM_DLLS = {
    "bcrypt.dll",
    "dwmapi.dll",
    "gdi32.dll",
    "gdiplus.dll",
    "iphlpapi.dll",
    "kernel32.dll",
    "msvcrt.dll",
    "opengl32.dll",
    "shell32.dll",
    "user32.dll",
    "ws2_32.dll",
    "advapi32.dll",
    "ole32.dll",
    "oleaut32.dll",
    "psapi.dll",
    "comdlg32.dll",
}


def check(archive, tag):
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Expected a version tag such as v0.1.0")
    expected_name = f"Isaac-LAN-{tag}-windows-x86.zip"
    if archive.name != expected_name:
        raise ValueError("Unexpected release archive name")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_suffix(".zip.sha256")
    if checksum.read_text(encoding="ascii").strip() != f"{digest}  {archive.name}":
        raise ValueError("Release archive checksum differs")
    prefix = archive.stem + "/"
    imports = {}
    with ZipFile(archive) as zipped:
        names = zipped.namelist()
        if len(names) != len(FILES) or set(names) != {prefix + name for name in FILES}:
            raise ValueError("Release archive contains missing or unexpected files")
        if zipped.testzip() is not None:
            raise ValueError("Release archive is damaged")
        payload = json.loads(zipped.read(prefix + "payload.json"))
        if (
            payload.get("format") != 1
            or payload.get("game_build") != "1.9.7.17.J460"
            or payload.get("extension_version") != tag[1:]
            or set(payload["files"]) != BINARIES
        ):
            raise ValueError("Release manifest differs")
        for name in sorted(BINARIES):
            contents = zipped.read(prefix + name)
            if hashlib.sha256(contents).hexdigest() != payload["files"][name]:
                raise ValueError(f"Package file hash differs: {name}")
            pe = pefile.PE(data=contents, fast_load=True)
            try:
                if pe.FILE_HEADER.Machine != 0x14C or pe.OPTIONAL_HEADER.Magic != 0x10B:
                    raise ValueError(f"Expected a 32-bit x86 PE file: {name}")
                is_dll = bool(pe.FILE_HEADER.Characteristics & 0x2000)
                if is_dll != name.endswith(".dll"):
                    raise ValueError(f"Unexpected PE file kind: {name}")
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
                imports[name] = required
            finally:
                pe.close()
        for name in ("Install.cmd", "Uninstall.cmd"):
            contents = zipped.read(prefix + name)
            if b"\r\n" not in contents or b"install.ps1" not in contents:
                raise ValueError(f"Invalid Windows installer entry: {name}")
    return {"archive": str(archive), "tag": tag, "sha256": digest, "imports": imports}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    print(json.dumps(check(args.archive, args.tag), indent=2))
