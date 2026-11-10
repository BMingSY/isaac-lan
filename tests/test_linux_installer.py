import errno
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys

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


@pytest.mark.parametrize("signature_name", ["Entity.DynamicCast", "Entity.RTTI", "NPC.RTTI"])
def test_refuses_bad_game_code_and_tampered_package(package_game, signature_name):
    package, game = package_game
    profile = json.loads((package / "game-profile.json").read_text())
    executable = game / "isaac-ng.exe"
    image = bytearray(executable.read_bytes())
    signature = next(entry for entry in profile["signatures"] if entry["name"] == signature_name)
    image[signature["rva"]] ^= 1
    executable.write_bytes(image)
    assert not installer.install(package, game, "Status")["gameCompatible"]
    with pytest.raises(ValueError, match="code differs"):
        installer.install(package, game)
    assert not (game / "winmm.dll").exists()
    (package / "winmm.dll").write_bytes(b"tampered")
    with pytest.raises(ValueError, match="verification"):
        installer.install(package, game)


def installed_files(game):
    paths = [game / name for name in installer.OWNED] + [
        game / ".isaac-lan-install",
        game / "isaac-lan/installation.json",
    ]
    return {path: path.read_bytes() if path.exists() else None for path in paths}


@pytest.mark.parametrize("mode", ["Install", "Uninstall"])
def test_missing_owned_files_can_be_repaired_or_uninstalled(package_game, mode):
    package, game = package_game
    installer.install(package, game)
    (game / "winmm.dll").unlink()
    result = installer.install(package, game, mode)
    assert result["installed"] == (mode == "Install")
    if mode == "Install":
        assert (game / "winmm.dll").read_bytes() == (package / "winmm.dll").read_bytes()
    else:
        assert all(value is None for value in installed_files(game).values())
    assert not list(game.glob(".isaac-lan-transaction-*"))


@pytest.mark.parametrize(
    "content", ["{", "null", "[]", '{"format": 1}', '{"format": 1, "files": []}']
)
@pytest.mark.parametrize("record", [False, True])
def test_malformed_manifests_report_actionable_error_without_changes(package_game, content, record):
    package, game = package_game
    if record:
        installer.install(package, game)
    path = game / "isaac-lan/installation.json" if record else package / "payload.json"
    path.write_text(content)
    before = installed_files(game)
    with pytest.raises(installer.InstallerError) as caught:
        installer.install(package, game)
    code = "INSTALLATION_INVALID" if record else "PACKAGE_INVALID"
    message = installer.error_message(caught.value)
    assert f"[{code}]" in message
    assert "Next step:" in message
    assert installed_files(game) == before


@pytest.mark.parametrize(
    "missing", ["payload.json", "winmm.dll", "isaac_lan_check.exe", "game-profile.json"]
)
def test_missing_package_file_names_file_and_reextract_action(package_game, missing):
    package, game = package_game
    (package / missing).unlink()
    with pytest.raises(installer.InstallerError) as caught:
        installer.install(package, game)
    message = installer.error_message(caught.value)
    assert "[PACKAGE_INVALID]" in message
    assert missing in message
    assert "Extract the entire release ZIP" in message
    assert all(value is None for value in installed_files(game).values())


def test_cli_bad_path_has_nonzero_exit_and_no_traceback(package_game):
    package, game = package_game
    result = subprocess.run(
        [sys.executable, str(package / "install.py"), "--game-directory", str(game / "missing")],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 1
    assert "[GAME_PATH]" in result.stderr
    assert "Browse local files" in result.stderr
    assert "Traceback" not in result.stderr
    assert not result.stdout


def test_running_game_refuses_mutation_but_status_is_read_only(package_game, monkeypatch):
    package, game = package_game
    monkeypatch.setattr(installer, "game_running", lambda: True)
    assert installer.install(package, game, "Status")["gameCompatible"]
    with pytest.raises(installer.InstallerError) as caught:
        installer.install(package, game)
    assert "[GAME_RUNNING]" in installer.error_message(caught.value)
    assert all(value is None for value in installed_files(game).values())


@pytest.mark.parametrize(
    "error_number,code",
    [
        (errno.EACCES, "PERMISSION_DENIED"),
        (errno.ENOSPC, "DISK_FULL"),
        (errno.EBUSY, "FILE_IN_USE"),
    ],
)
def test_io_failure_reports_cause_and_restores_files(package_game, monkeypatch, error_number, code):
    package, game = package_game
    installer.install(package, game)
    before = installed_files(game)
    payload = json.loads((package / "payload.json").read_text())
    (package / "winmm.dll").write_bytes(b"new version")
    payload["files"]["winmm.dll"] = installer.digest(package / "winmm.dll")
    (package / "payload.json").write_text(json.dumps(payload))
    replace = installer.os.replace
    failed = False

    def fail_once(source, target):
        nonlocal failed
        if not failed and target.name == "installation.json":
            failed = True
            raise OSError(error_number, "injected failure", str(target))
        return replace(source, target)

    monkeypatch.setattr(installer.os, "replace", fail_once)
    with pytest.raises(OSError) as caught:
        installer.install(package, game)
    message = installer.error_message(caught.value)
    assert f"[{code}]" in message
    assert "installation.json" in message
    assert installed_files(game) == before
    assert not list(game.glob(".isaac-lan-transaction-*"))


def test_uninstall_failure_restores_deleted_files(package_game, monkeypatch):
    package, game = package_game
    installer.install(package, game)
    before = installed_files(game)
    unlink = Path.unlink
    failed = False

    def fail_once(path, *args, **kwargs):
        nonlocal failed
        if not failed and path == game / "isaac-lan/installation.json":
            failed = True
            raise PermissionError(errno.EACCES, "injected delete failure", str(path))
        return unlink(path, *args, **kwargs)

    monkeypatch.setattr(Path, "unlink", fail_once)
    with pytest.raises(PermissionError):
        installer.install(package, game, "Uninstall")
    assert installed_files(game) == before


def test_failed_rollback_keeps_all_backups_and_restores_remaining_files(package_game, monkeypatch):
    package, game = package_game
    installer.install(package, game)
    before = installed_files(game)
    payload = json.loads((package / "payload.json").read_text())
    for name in installer.OWNED:
        (package / name).write_bytes(b"new version")
        payload["files"][name] = installer.digest(package / name)
    (package / "payload.json").write_text(json.dumps(payload))
    replace = installer.os.replace

    def fail_write_and_one_restore(source, target):
        if target.name == "installation.json" or (
            source.name.startswith("rollback-") and target.name == "isaac_lan_probe.dll"
        ):
            raise PermissionError(errno.EACCES, "injected persistent failure", str(target))
        return replace(source, target)

    monkeypatch.setattr(installer.os, "replace", fail_write_and_one_restore)
    with pytest.raises(installer.InstallerError) as caught:
        installer.install(package, game)
    message = installer.error_message(caught.value)
    assert "[ROLLBACK_FAILED]" in message
    assert "Do not start the game" in message
    assert (game / "winmm.dll").read_bytes() == before[game / "winmm.dll"]
    assert (game / "isaac_lan_probe.dll").read_bytes() == b"new version"
    (recovery,) = game.glob(".isaac-lan-transaction-*")
    assert str(recovery) in message
    manifest = json.loads((recovery / "recovery.json").read_text())
    for entry in manifest["files"]:
        assert (recovery / entry["backup"]).read_bytes() == before[Path(entry["path"])]


def test_cleanup_failure_does_not_report_a_completed_install_as_failed(
    package_game, monkeypatch, capsys
):
    package, game = package_game

    def fail_cleanup(path):
        raise PermissionError(errno.EACCES, "injected cleanup failure", str(path))

    monkeypatch.setattr(installer.shutil, "rmtree", fail_cleanup)
    assert installer.install(package, game)["installed"]
    assert "Could not remove temporary folder" in capsys.readouterr().err
    assert (game / "winmm.dll").read_bytes() == (package / "winmm.dll").read_bytes()


@pytest.mark.parametrize("missing", [".isaac-lan-install", "isaac-lan/installation.json"])
def test_incomplete_ownership_record_is_preserved(package_game, missing):
    package, game = package_game
    installer.install(package, game)
    (game / missing).unlink()
    before = installed_files(game)
    with pytest.raises(installer.InstallerError) as caught:
        installer.install(package, game)
    assert "[INSTALLATION_INVALID]" in installer.error_message(caught.value)
    assert installed_files(game) == before
