import hashlib
import importlib.util
import json
from pathlib import Path
import struct

import pytest

from tools.build_package import game_profile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("linux_install", ROOT / "package/install.py")
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


@pytest.fixture
def package_game(tmp_path, monkeypatch):
    package, game = tmp_path / "package", tmp_path / "game"
    package.mkdir()
    game.mkdir()
    profile = game_profile(ROOT)
    size = profile["minimum_image_size"] + 0x1000
    image = bytearray(size)
    image[:2] = b"MZ"
    struct.pack_into("<I", image, 60, 128)
    image[128:132] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", image, 132, 0x14C, 3, 0, 0, 0, 224, 2)
    struct.pack_into("<H", image, 152, 0x10B)
    struct.pack_into("<I", image, 208, size)
    for index, section in enumerate(profile["sections"]):
        struct.pack_into(
            "<8sIIIIIIHHI",
            image,
            376 + index * 40,
            b"section",
            section["size"],
            section["start"],
            section["size"],
            section["start"],
            0,
            0,
            0,
            0,
            section["flags"],
        )
    marker = profile["game_build"].encode() + b"-"
    image[profile["version_rva"] : profile["version_rva"] + len(marker)] = marker
    for signature in profile["signatures"]:
        image[signature["rva"] : signature["rva"] + 16] = bytes.fromhex(signature["bytes"])
    (game / "isaac-ng.exe").write_bytes(image)
    (game / "save.dat").write_bytes(b"keep the original save")
    (package / "game-profile.json").write_text(json.dumps(profile))
    (package / "install.py").write_bytes((ROOT / "package/install.py").read_bytes())
    files = {}
    for name in (*installer.OWNED, "isaac_lan_check.exe"):
        (package / name).write_bytes(name.encode())
        files[name] = installer.digest(package / name)
    payload = {
        "format": 1,
        "game_build": profile["game_build"],
        "files": files,
        "linux_files": {
            name: installer.digest(package / name) for name in ("install.py", "game-profile.json")
        },
    }
    (package / "payload.json").write_text(json.dumps(payload))
    monkeypatch.setattr(installer, "game_running", lambda: False)
    return package, game


def test_install_upgrade_status_uninstall_preserves_game_and_logs(package_game):
    package, game = package_game
    original = hashlib.sha256((game / "isaac-ng.exe").read_bytes()).hexdigest()
    assert installer.install(package, game)["installed"]
    assert installer.install(package, game, "Status")["gameCompatible"]
    (game / "isaac-lan/probe.log").write_text("preserve diagnostics")
    payload = json.loads((package / "payload.json").read_text())
    (package / "isaac_lan_probe.dll").write_bytes(b"new version")
    payload["files"]["isaac_lan_probe.dll"] = installer.digest(package / "isaac_lan_probe.dll")
    (package / "payload.json").write_text(json.dumps(payload))
    assert installer.install(package, game)["installed"]
    assert (game / "isaac_lan_probe.dll").read_bytes() == b"new version"
    assert not installer.install(package, game, "Uninstall")["installed"]
    assert (game / "isaac-lan/probe.log").read_text() == "preserve diagnostics"
    assert (game / "save.dat").read_bytes() == b"keep the original save"
    assert hashlib.sha256((game / "isaac-ng.exe").read_bytes()).hexdigest() == original


@pytest.mark.parametrize("kind", ["foreign", "symlink", "changed-installed"])
def test_refuses_unowned_or_changed_files(package_game, kind):
    package, game = package_game
    if kind == "changed-installed":
        installer.install(package, game)
    target = game / "winmm.dll"
    if kind == "symlink":
        target.symlink_to(game / "save.dat")
    else:
        target.write_bytes(b"belongs to another extension")
    before = target.read_bytes()
    with pytest.raises(ValueError):
        installer.install(package, game)
    assert target.read_bytes() == before


@pytest.mark.parametrize("installed", [False, True])
def test_failed_transaction_restores_all_files(package_game, monkeypatch, installed):
    package, game = package_game
    if installed:
        installer.install(package, game)
    paths = [game / name for name in installer.OWNED] + [
        game / ".isaac-lan-install",
        game / "isaac-lan/installation.json",
    ]
    before = {path: path.read_bytes() if path.exists() else None for path in paths}
    replace = installer.os.replace
    failed = False

    def fail_once(source, target):
        nonlocal failed
        if not failed and target.name == "installation.json":
            failed = True
            raise OSError("injected write failure")
        return replace(source, target)

    monkeypatch.setattr(installer.os, "replace", fail_once)
    with pytest.raises(OSError):
        installer.install(package, game)
    assert {path: path.read_bytes() if path.exists() else None for path in paths} == before


def test_refuses_bad_game_code_and_tampered_package(package_game):
    package, game = package_game
    profile = json.loads((package / "game-profile.json").read_text())
    executable = game / "isaac-ng.exe"
    image = bytearray(executable.read_bytes())
    image[profile["signatures"][0]["rva"]] ^= 1
    executable.write_bytes(image)
    assert not installer.install(package, game, "Status")["gameCompatible"]
    with pytest.raises(ValueError, match="code differs"):
        installer.install(package, game)
    assert not (game / "winmm.dll").exists()
    (package / "winmm.dll").write_bytes(b"tampered")
    with pytest.raises(ValueError, match="verification"):
        installer.install(package, game)
