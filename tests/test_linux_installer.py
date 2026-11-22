import errno
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import pytest

from tools.build_package import build_bundle, game_profile
from tools.testing.installer import game_image

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
    image = game_image(profile)
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
        "backend": profile["backend"],
        "files": files,
        "linux_files": {
            name: installer.digest(package / name) for name in ("install.py", "game-profile.json")
        },
    }
    (package / "payload.json").write_text(json.dumps(payload))
    monkeypatch.setattr(installer, "game_running", lambda game: False)
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
        (game / "isaac_lan_probe.dll").unlink()
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


@pytest.fixture
def universal_bundle(tmp_path):
    builds = []
    profiles = {}
    for backend in ("j511", "j835"):
        build = tmp_path / backend
        build.mkdir()
        profiles[backend] = game_profile(ROOT, backend)
        (build / "game-profile.json").write_text(json.dumps(profiles[backend]))
        for name in (*installer.OWNED, "isaac_lan_check.exe"):
            (build / name).write_bytes(f"{backend}/{name}".encode())
        builds.append(build)
    bundle = tmp_path / "universal"
    build_bundle(builds, bundle)
    return bundle, profiles


def test_bundle_routes_installs_upgrades_game_switch_and_uninstall(package_game, universal_bundle):
    legacy, game = package_game
    installer.install(legacy, game)
    bundle, profiles = universal_bundle
    assert installer.install(bundle, game)["installed"]
    record = json.loads((game / "isaac-lan/installation.json").read_text())
    assert record["format"] == 2
    assert not (game / "isaac_lan_probe.dll").exists()
    assert (game / "winmm.dll").read_bytes() == (bundle / "winmm.dll").read_bytes()
    for backend, profile in profiles.items():
        (game / "isaac-ng.exe").write_bytes(game_image(profile))
        assert installer.install(bundle, game, "Status")["gameBuild"] == profile["game_build"]
        assert record["backends"][backend] == profile["game_build"]
        target = game / "isaac-lan/backends" / backend / "isaac_lan_probe.dll"
        assert target.read_bytes() == f"{backend}/isaac_lan_probe.dll".encode()
    before = installed_files(game)
    (game / "isaac-ng.exe").write_bytes(b"unsupported")
    assert not installer.install(bundle, game, "Status")["gameCompatible"]
    with pytest.raises(installer.InstallerError) as caught:
        installer.install(bundle, game)
    assert caught.value.code == "GAME_INCOMPATIBLE"
    assert installed_files(game) == before
    assert not installer.install(bundle, game, "Uninstall")["installed"]
    assert not (game / "isaac-lan/backends").exists()
    assert (game / "save.dat").read_bytes() == b"keep the original save"


def test_bundle_repair_and_rollback_both_named_probes(package_game, universal_bundle, monkeypatch):
    _, game = package_game
    bundle, profiles = universal_bundle
    installer.install(bundle, game)
    record = game / "isaac-lan/installation.json"
    installed = json.loads(record.read_text())
    originals = {name: (game / name).read_bytes() for name in installed["files"]}
    for backend in profiles:
        directory = bundle / "backends" / backend
        probe = directory / "isaac_lan_probe.dll"
        probe.write_bytes(backend.encode())
        manifest = json.loads((directory / "payload.json").read_text())
        manifest["files"][probe.name] = installer.digest(probe)
        (directory / "payload.json").write_text(json.dumps(manifest))
    replace = installer.os.replace

    def fail_record(source, target):
        if target == record:
            raise OSError("record write failed")
        return replace(source, target)

    with monkeypatch.context() as m:
        m.setattr(installer.os, "replace", fail_record)
        with pytest.raises(OSError, match="record write failed"):
            installer.install(bundle, game)
    assert json.loads(record.read_text()) == installed
    assert {n: (game / n).read_bytes() for n in originals} == originals
    (game / installer.backend_file("j835")).unlink()
    assert installer.install(bundle, game)["installed"]
    assert (game / installer.backend_file("j835")).read_bytes() == b"j835"
    extra = game / "isaac-lan/backends/j835/player.txt"
    extra.write_text("keep")
    installer.install(bundle, game, "Uninstall")
    assert extra.read_text() == "keep"
    assert not (game / "isaac-lan/backends/j511").exists()


def test_bundle_upgrade_retires_the_recorded_j510_probe(package_game, universal_bundle):
    _, game = package_game
    bundle, _ = universal_bundle
    installer.install(bundle, game)
    record = game / "isaac-lan/installation.json"
    prior = json.loads(record.read_text())
    old_probe = installer.backend_file("j510")
    new_probe = installer.backend_file("j511")
    (game / new_probe).parent.rename((game / old_probe).parent)
    (game / old_probe).write_bytes(b"previous J510 DLL")
    prior["backends"].pop("j511")
    prior["backends"]["j510"] = "1.9.7.19.J510"
    prior["files"].pop(new_probe)
    prior["files"][old_probe] = installer.digest(game / old_probe)
    record.write_text(json.dumps(prior))
    unrelated = (game / old_probe).with_name("player.txt")
    unrelated.write_text("keep")

    assert installer.install(bundle, game)["installed"]
    assert not (game / old_probe).exists()
    assert (game / new_probe).read_bytes() == (
        bundle / "backends/j511/isaac_lan_probe.dll"
    ).read_bytes()
    assert json.loads(record.read_text())["backends"] == {
        "j511": "1.9.7.19.J511",
        "j835": "1.7.9b.J835",
    }
    assert unrelated.read_text() == "keep"


def test_bundle_preserves_foreign_target_and_rejects_symlinked_parent(
    package_game, universal_bundle, tmp_path
):
    _, game = package_game
    bundle, _ = universal_bundle
    parent = game / "isaac-lan/backends"
    parent.mkdir(parents=True)
    external = tmp_path / "external"
    external.mkdir()
    (parent / "j835").symlink_to(external, target_is_directory=True)
    with pytest.raises(installer.InstallerError, match="ordinary directory"):
        installer.install(bundle, game)
    assert list(external.iterdir()) == []
    (parent / "j835").unlink()
    (parent / "j835").mkdir()
    foreign = game / installer.backend_file("j835")
    foreign.write_bytes(b"foreign")
    with pytest.raises(installer.InstallerError) as caught:
        installer.install(bundle, game)
    assert caught.value.code == "FILE_CONFLICT"
    assert foreign.read_bytes() == b"foreign" and not (game / "winmm.dll").exists()


def test_concurrent_installer_leaves_directory_untouched(package_game):
    fcntl = pytest.importorskip("fcntl")

    package, game = package_game
    lock = installer.os.open(game, installer.os.O_RDONLY | installer.os.O_DIRECTORY)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with pytest.raises(installer.InstallerError) as caught:
            installer.install(package, game)
        assert caught.value.code == "FILE_IN_USE"
        assert not (game / "winmm.dll").exists()
    finally:
        installer.os.close(lock)
    assert installer.install(package, game)["installed"]


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
    if record:
        result = installer.install(package, game)
        backup = Path(result["backupDirectory"]) / "old-installation.json"
        assert backup.read_text() == content
        assert (
            json.loads(path.read_text())["files"]
            == json.loads((package / "payload.json").read_text())["files"]
        )
    else:
        before = installed_files(game)
        with pytest.raises(installer.InstallerError) as caught:
            installer.install(package, game)
        assert "[PACKAGE_INVALID]" in installer.error_message(caught.value)
        assert installed_files(game) == before


def test_damaged_marker_recovery_requires_an_installed_record(package_game):
    package, game = package_game
    marker = game / ".isaac-lan-install"
    marker.write_bytes(b"unrecognized")
    with pytest.raises(installer.InstallerError, match="Unrecognized installation marker"):
        installer.install(package, game)
    assert marker.read_bytes() == b"unrecognized"
    marker.unlink()
    installer.install(package, game)
    marker.write_bytes(b"damaged")
    result = installer.install(package, game)
    assert marker.read_text().strip() == "IsaacLAN/1"
    assert (Path(result["backupDirectory"]) / "old-.isaac-lan-install").read_bytes() == b"damaged"


@pytest.mark.parametrize("missing", ["payload.json", "winmm.dll", "game-profile.json"])
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
    monkeypatch.setattr(installer, "game_running", lambda game: True)
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
@pytest.mark.parametrize("mode", ["Install", "Uninstall"])
def test_incomplete_ownership_can_be_repaired_or_removed(package_game, missing, mode):
    package, game = package_game
    installer.install(package, game)
    (game / missing).unlink()
    result = installer.install(package, game, mode)
    assert result["installed"] == (mode == "Install")
    assert all((game / name).exists() == result["installed"] for name in installer.OWNED)
    assert (game / missing).exists() == result["installed"]


def test_manual_install_changed_proxy_and_missing_game(package_game):
    package, game = package_game
    (package / "isaac_lan_check.exe").unlink()
    for name in installer.OWNED:
        (game / name).write_bytes((package / name).read_bytes())
    assert installer.install(package, game / "isaac-ng.exe")["installed"]
    (game / "winmm.dll").write_bytes(b"other extension")
    (game / "isaac-ng.exe").unlink()
    (package / "payload.json").unlink()
    result = installer.install(package, game, "Uninstall")
    assert result["preservedFiles"] == ["winmm.dll"]
    assert (game / "winmm.dll").read_bytes() == b"other extension"
    assert not installer.install(package, game, "Uninstall")["installed"]
    assert not (game / "isaac_lan_probe.dll").exists()
    assert not (game / ".isaac-lan-install").exists()


def test_remove_manual_installation_after_game_and_checker_files_are_removed(package_game):
    package, game = package_game
    for name in installer.OWNED:
        (game / name).write_bytes((package / name).read_bytes())
    (game / "isaac-ng.exe").unlink()
    (package / "game-profile.json").unlink()
    assert not installer.install(package, game, "Uninstall")["installed"]
    assert all(not (game / name).exists() for name in installer.OWNED)
    (package / "payload.json").write_text("damaged")
    assert not installer.install(package, game, "Uninstall")["installed"]


def test_reinstall_identical_package_while_game_is_running(package_game, monkeypatch):
    package, game = package_game
    installer.install(package, game)
    monkeypatch.setattr(installer, "game_running", lambda game: True)
    assert installer.install(package, game)["installed"]
    (game / "isaac_lan_probe.dll").unlink()
    with pytest.raises(installer.InstallerError, match="still running"):
        installer.install(package, game)


def test_repair_backs_up_modified_project_dll(package_game):
    package, game = package_game
    installer.install(package, game)
    probe = game / "isaac_lan_probe.dll"
    probe.write_bytes(b"local build")
    result = installer.install(package, game)
    assert (
        Path(result["backupDirectory"]) / "old-isaac_lan_probe.dll"
    ).read_bytes() == b"local build"
    assert probe.read_bytes() == (package / probe.name).read_bytes()


def test_running_proton_process_belongs_to_selected_directory(tmp_path):
    proc = tmp_path / "proc"
    pid = proc / "123"
    pid.mkdir(parents=True)
    game = tmp_path / "steam library" / "game"
    game.mkdir(parents=True)
    other = tmp_path / "other"
    other.mkdir()
    (pid / "cwd").symlink_to(game, target_is_directory=True)
    (pid / "cmdline").write_bytes(b"wine64\0isaac-ng.exe\0")
    assert installer.game_running(game, proc)
    assert not installer.game_running(other, proc)
    (pid / "cmdline").write_bytes(b"python3\0install.py\0--game-directory\0isaac-ng.exe\0")
    assert not installer.game_running(game, proc)
