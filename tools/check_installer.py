#!/usr/bin/env python3
"""Exercise the Windows installer only in a new disposable directory; no game launch."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import struct
from build_package import build
from game_profiles import build_profile
from testing.installer import game_image


def windows(path):
    return subprocess.check_output(["wslpath", "-w", str(path.resolve())], text=True).strip()


def check(game, build_directory, output):
    output.mkdir(parents=True, exist_ok=False)
    (output / ".isaac-lan-lab").write_text("Installer validation; never launched.\n")
    target = output / "game"
    target.mkdir()
    shutil.copy2(game / "isaac-ng.exe", target)
    sentinel = target / "mods/keep/main.lua"
    sentinel.parent.mkdir(parents=True)
    sentinel.write_text("-- Unrelated mod must remain byte-identical.\n")
    preserved = [sentinel]
    for name in ("bootstp.dll", "language_unlocker.dll"):
        if (game / name).is_file():
            shutil.copy2(game / name, target / name)
            preserved.append(target / name)
    for mod in (game / "mods").glob("*3568677664*"):
        if mod.is_dir():
            destination = target / "mods" / mod.name
            shutil.copytree(mod, destination)
            preserved.extend(p for p in destination.rglob("*") if p.is_file())
    preserved_hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in preserved}
    original_exe = hashlib.sha256((target / "isaac-ng.exe").read_bytes()).hexdigest()
    package = output / "package"
    payload = build(build_directory, package)
    transcript = []

    def run(mode="Install", success=True):
        result = subprocess.run(
            [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                windows(package / "install.ps1"),
                "-Mode",
                mode,
                "-GameDirectory",
                windows(target),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=30,
        )
        transcript.append({"mode": mode, "exit_code": result.returncode, "output": result.stdout})
        (output / "transcript.json").write_text(json.dumps(transcript, indent=2))
        assert (result.returncode == 0) == success, result.stdout
        assert all(
            p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest() == digest
            for p, digest in preserved_hashes.items()
        ), "Installer changed an unrelated mod or native language patch"
        return result.stdout

    def valid_payload():
        assert (target / ".isaac-lan-install").read_text() == "IsaacLAN/1\n"
        for name, digest in payload["files"].items():
            if name == "isaac_lan_check.exe":
                continue  # Read-only installer helper, not a game DLL.
            assert hashlib.sha256((target / name).read_bytes()).hexdigest() == digest

    run("Status")
    (target / "winmm.dll").write_bytes(b"Other extension: preserve me")
    run(success=False)
    assert (target / "winmm.dll").read_bytes() == b"Other extension: preserve me"
    (target / "winmm.dll").unlink()
    run()
    valid_payload()
    run()
    valid_payload()  # Upgrade/reinstall ownership checks.
    (target / "isaac-lan/session.keep").write_bytes(b"User session data")
    (target / "winmm.dll").write_bytes(b"Modified outside installer")
    run("Uninstall")
    assert not (target / "isaac_lan_probe.dll").exists()
    assert (target / "winmm.dll").read_bytes() == b"Modified outside installer"
    shutil.copy2(package / "winmm.dll", target)
    run("Uninstall")
    assert not (target / ".isaac-lan-install").exists()
    assert not any((target / name).exists() for name in payload["files"])
    assert (target / "isaac-lan/session.keep").read_bytes() == b"User session data"
    run("Uninstall")
    assert hashlib.sha256((target / "isaac-ng.exe").read_bytes()).hexdigest() == original_exe
    executable = (target / "isaac-ng.exe").read_bytes()
    profile = build_profile(build_directory)
    clean = game_image(profile)
    patched = bytearray(clean)
    pe = struct.unpack_from("<I", clean, 0x3C)[0]
    struct.pack_into("<I", patched, pe + 8, 1)  # Timestamp metadata.
    patched.extend(b"Unrelated patch metadata\0")
    wrong_version = bytearray(clean)
    wrong_version[profile["version_rva"]] ^= 1
    wrong_arch = bytearray(clean)
    struct.pack_into("<H", wrong_arch, pe + 4, 0x8664)
    variants = [
        ("installed_" + profile["backend"], executable, True, True),
        ("unrelated_patch", patched, True, True),
        ("wrong_version", wrong_version, False, False),
        ("wrong_architecture", wrong_arch, False, False),
        ("truncated_file", clean[:1024], False, False),
    ]
    signatures = {s["name"].replace(".", "").lower(): s for s in profile["signatures"]}
    conflicts = {}
    for label, name in [
        ("changed_engine_entry", "gameupdate"),
        ("changed_console_update", "consoleupdate"),
        ("changed_console_command", "consoleruncommand"),
    ]:
        signature = signatures[name]
        offset = next(i for i in range(16) if signature["mask"] & (1 << i))
        conflicting = bytearray(clean)
        conflicting[signature["rva"] + offset] ^= 1
        conflicts[label] = f"{signature['name']} at RVA 0x{signature['rva']:08x}"
        variants.append((label, conflicting, True, False))
    results = {}
    for label, data, install_ok, code_ok in variants:
        (target / "isaac-ng.exe").write_bytes(data)
        run(success=install_ok)
        if install_ok:
            valid_payload()
            run("Uninstall")
        checked = subprocess.run(
            [str(package / "isaac_lan_check.exe"), "--code", windows(target / "isaac-ng.exe")],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=30,
        )
        assert (checked.returncode == 0) == code_ok, (label, checked.stdout)
        if label in conflicts:
            assert conflicts[label] in checked.stdout, checked.stdout
        assert (target / "isaac-ng.exe").read_bytes() == data
        results[label] = {
            "installation_allowed": install_ok,
            "entry_points_match": code_ok,
            "detail": checked.stdout.strip(),
        }
    (target / "isaac-ng.exe").write_bytes(executable)
    checker = package / "isaac_lan_check.exe"
    checker_bytes = checker.read_bytes()
    checker.write_bytes(checker_bytes + b"tampered")
    # Windows PowerShell wraps long Write-Error lines to the console width.
    assert "Packagefilefailedverification:isaac_lan_check.exe" in "".join(
        run(success=False).split()
    )
    checker.write_bytes(checker_bytes)
    (target / "isaac-ng.exe").write_bytes(b"Unsupported version fixture")
    run(success=False)
    assert not any((target / name).exists() for name in payload["files"])
    assert sentinel.read_text() == "-- Unrelated mod must remain byte-identical.\n"
    return {
        "install": True,
        "reinstall": True,
        "uninstall": True,
        "foreign_proxy_preserved": True,
        "language_patch_files_preserved": len(preserved_hashes) - 1,
        "changed_file_preserved": True,
        "unsupported_game_rejected": True,
        "session_data_preserved": True,
        "game_launched": False,
        "build_variants": results,
        "checker_tampering_rejected": True,
        "files": payload["files"],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = check(args.game, args.build, args.output)
    (args.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
