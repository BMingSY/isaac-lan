"""Restoring a suite must preserve personal data even on partial failure."""

from pathlib import Path
from types import SimpleNamespace
import json
import subprocess
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import lab_profile


@pytest.mark.parametrize("paths", [[], ["/lab/game/isaac-ng.exe"], ["/other/game/isaac-ng.exe"]])
@pytest.mark.parametrize("exclusive", [False, True])
def test_performance_requires_an_idle_machine(monkeypatch, paths, exclusive):
    monkeypatch.setattr(lab_profile, "windows", str)
    monkeypatch.setattr(
        lab_profile.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(stdout=json.dumps(paths)),
    )
    if paths and (exclusive or paths[0].startswith("/lab/")):
        with pytest.raises(RuntimeError):
            lab_profile.idle([Path("/lab")], exclusive=exclusive)
    else:
        lab_profile.idle([Path("/lab")], exclusive=exclusive)


@pytest.fixture
def protected(tmp_path, monkeypatch):
    monkeypatch.setattr(lab_profile, "idle", lambda labs: None)
    labs = [tmp_path / role for role in ("host", "client")]
    for lab in labs:
        lab.mkdir()
        (lab / ".isaac-lan-lab").touch()
        (lab / "profile").mkdir()
        (lab / "profile/save.dat").write_bytes(b"personal save")
    return lab_profile.ProtectedLabs(labs, tmp_path / "results")


def mutate(protected):
    for lab in protected.labs:
        (lab / "profile/save.dat").write_bytes(b"test save")
        (lab / "game/data").mkdir(parents=True)
        (lab / "game/data/test.dat").write_bytes(b"test data")


def test_restores_exact_files_and_removes_created_directories(protected):
    mutate(protected)
    result = protected.restore()
    assert result == {source: entry["before"] for source, entry in protected.report().items()}
    for lab in protected.labs:
        assert (lab / "profile/save.dat").read_bytes() == b"personal save"
        assert not (lab / "game/data").exists()


@pytest.mark.parametrize("failure", ["running", "corrupt", "missing"])
def test_preflight_failure_never_replaces_live_data(protected, monkeypatch, failure):
    mutate(protected)
    if failure == "running":

        def busy(labs):
            raise RuntimeError("running game")

        monkeypatch.setattr(lab_profile, "idle", busy)
    else:
        backup = protected.entries[-3].destination / "save.dat"
        if failure == "corrupt":
            backup.write_bytes(b"corrupt")
        else:
            backup.unlink()
    with pytest.raises(RuntimeError):
        protected.restore()
    for lab in protected.labs:
        assert (lab / "profile/save.dat").read_bytes() == b"test save"
        assert (lab / "game/data/test.dat").exists()


def test_one_failed_restore_still_restores_other_lab(protected, monkeypatch):
    mutate(protected)
    copytree = lab_profile.shutil.copytree

    def fail_first(source, destination):
        if destination == protected.labs[0] / "profile":
            raise OSError("injected copy failure")
        return copytree(source, destination)

    monkeypatch.setattr(lab_profile.shutil, "copytree", fail_first)
    with pytest.raises(RuntimeError, match="injected copy failure"):
        protected.restore()
    assert (protected.labs[1] / "profile/save.dat").read_bytes() == b"personal save"
    assert not (protected.labs[1] / "game/data").exists()
    assert (protected.entries[0].destination / "save.dat").read_bytes() == b"personal save"


def test_another_suite_cannot_enter_until_restoration_finishes(protected, tmp_path):
    script = """
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import lab_profile
lab_profile.idle = lambda labs: None
try:
    owner = lab_profile.ProtectedLabs([Path(p) for p in sys.argv[2:4]], Path(sys.argv[4]))
except RuntimeError as error:
    assert 'Owned lab in use' in str(error), str(error)
    print('busy')
else:
    owner.restore()
    print('acquired')
"""

    def enter(output):
        return subprocess.run(
            [
                sys.executable,
                "-c",
                script,
                str(Path(lab_profile.__file__).parent),
                *(str(lab) for lab in protected.labs),
                str(output),
            ],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    mutate(protected)
    assert enter(tmp_path / "overlap") == "busy"
    assert not (tmp_path / "overlap").exists()
    protected.restore()
    assert enter(tmp_path / "next") == "acquired"


def test_failed_backup_releases_lab_ownership(protected, tmp_path, monkeypatch):
    protected.restore()
    copytree = lab_profile.shutil.copytree

    def fail_copy(*args, **kwargs):
        raise OSError("injected backup failure")

    monkeypatch.setattr(lab_profile.shutil, "copytree", fail_copy)
    with pytest.raises(OSError, match="injected backup failure"):
        lab_profile.ProtectedLabs(protected.labs, tmp_path / "failed-backup")
    monkeypatch.setattr(lab_profile.shutil, "copytree", copytree)
    lab_profile.ProtectedLabs(protected.labs, tmp_path / "retry").restore()
