"""Exercise version selection through build artifacts, installers and owned labs."""

import copy
import json
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_package import build
from game_profiles import build_profile, lab_profile, profile_directory, source_profile, validate
from generate_game_profile import generate
from game_logs import log_path
from lab_profile import validate_startup
from progress_fixture import prepare


def fixture_profile():
    value = copy.deepcopy(source_profile())
    value.update(backend="fixture", game_build="fixture.2", documents_directory="Isaac Fixture")
    value["capabilities"]["native_emotes"] = False
    value["testing"] = {"progress_fixture": None, "accepted_beta_option": None}
    return value


def test_generated_profile_and_header_use_the_selected_backend(tmp_path):
    profile = generate("j460", tmp_path)
    assert build_profile(tmp_path) == source_profile() == profile
    assert profile["signatures"] and profile["capabilities"]["native_emotes"]
    # Compile the generated descriptor and observe its public values and catalog.
    source = tmp_path / "probe.cpp"
    source.write_text("""#include "engine/profile.h"
#include <cstdio>
int main() {
    const auto& p = isaac::engine::profile();
    std::printf("%s\\n%s\\n%s\\n%zu\\n", p.id, p.version, p.documentsDirectory, p.signatures.size());
}
""")
    executable = tmp_path / "probe"
    subprocess.run(
        [
            "c++",
            "-std=c++20",
            "-I",
            str(ROOT / "src"),
            "-I",
            str(tmp_path),
            str(source),
            str(ROOT / "src/engine/profile.cpp"),
            "-o",
            str(executable),
        ],
        check=True,
    )
    lines = subprocess.check_output([str(executable)], text=True).splitlines()
    assert lines == [
        profile["backend"],
        profile["game_build"],
        profile["documents_directory"],
        str(len(profile["signatures"])),
    ]


def test_package_uses_build_snapshot_instead_of_source_default(tmp_path):
    directory = tmp_path / "build"
    directory.mkdir()
    profile = fixture_profile()
    (directory / "game-profile.json").write_text(json.dumps(profile))
    for name in ("winmm.dll", "isaac_lan_probe.dll", "isaac_lan_check.exe"):
        (directory / name).write_bytes(name.encode())
    package = tmp_path / "package"
    payload = build(directory, package)
    assert payload["backend"] == "fixture"
    assert payload["game_build"] == "fixture.2"
    assert json.loads((package / "game-profile.json").read_text()) == profile
    (directory / "game-profile.json").unlink()
    with pytest.raises(FileNotFoundError):
        build(directory, tmp_path / "missing-profile")
    assert not (tmp_path / "missing-profile").exists()


def test_lab_uses_its_profile_and_refuses_an_unaudited_progress_fixture(tmp_path):
    (tmp_path / ".isaac-lan-lab").touch()
    profile = fixture_profile()
    (tmp_path / "game-profile.json").write_text(json.dumps(profile))
    directory = tmp_path / "profile/Documents/My Games/Isaac Fixture"
    directory.mkdir(parents=True)
    save = directory / "persistentgamedata1.dat"
    save.write_bytes(b"preserve another version's save")
    assert profile_directory(tmp_path) == directory
    assert log_path(tmp_path) == directory / "log.txt"
    validate_startup([tmp_path])
    with pytest.raises(ValueError, match="No audited progress fixture"):
        prepare(tmp_path, host=True)
    assert save.read_bytes() == b"preserve another version's save"
    # A malformed explicit profile must not fall back to J460.
    (tmp_path / "game-profile.json").write_text("{}")
    with pytest.raises(ValueError):
        lab_profile(tmp_path)


@pytest.mark.parametrize("directory", ["..", "../shared", "C:/shared", "a\\b"])
def test_profile_cannot_escape_the_owned_documents_directory(directory):
    profile = fixture_profile()
    profile["documents_directory"] = directory
    with pytest.raises(ValueError):
        validate(profile)


def test_unknown_backend_is_rejected_before_generating_files(tmp_path):
    with pytest.raises(FileNotFoundError):
        generate("unimplemented", tmp_path / "out")
    assert not (tmp_path / "out").exists()
    for name in ("../j460", "j460/../j460", "j460;main"):
        with pytest.raises(ValueError):
            source_profile(name)
