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
from game_profiles import (
    backend_metadata,
    build_profile,
    lab_profile,
    profile_directory,
    source_profile,
    validate,
)
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
    std::printf("%d\\n%s\\n%s\\n%s\\n%.1f\\n", p.presentation.nativeLobby,
        p.presentation.small.path, p.presentation.normal.path,
        p.presentation.heading.path, p.presentation.heading.scale);
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
        "1",
        profile["presentation"]["fonts"]["small"]["path"],
        profile["presentation"]["fonts"]["normal"]["path"],
        profile["presentation"]["fonts"]["heading"]["path"],
        "1.0",
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


@pytest.mark.parametrize(
    "path,scale",
    [
        ("font/../private.fnt", 1),
        ("font//private.fnt", 1),
        ("font/a\\b.fnt", 1),
        ("font/a\nb.fnt", 1),
        ("D:/font/a.fnt", 1),
        ("font/a.png", 1),
        ("font/a.fnt", float("nan")),
        ("font/a.fnt", float("inf")),
        ("font/a.fnt", 0),
        ("font/a.fnt", True),
    ],
)
def test_invalid_resource_metadata_is_rejected(path, scale):
    profile = fixture_profile()
    profile["presentation"]["fonts"]["small"] = {"path": path, "scale": scale}
    with pytest.raises(ValueError, match="menu font"):
        validate(profile)


def test_legacy_lab_snapshot_still_identifies_its_documents_directory(tmp_path):
    profile = fixture_profile()
    del profile["presentation"]
    (tmp_path / "game-profile.json").write_text(json.dumps(profile))
    assert profile_directory(tmp_path) == tmp_path / "profile/Documents/My Games/Isaac Fixture"


def test_repentance_backend_generates_original_capabilities(tmp_path):
    metadata = backend_metadata("j835")
    assert metadata["game_build"] == "1.7.9b.J835"
    assert metadata["documents_directory"] == "Binding of Isaac Repentance"
    assert metadata["capabilities"]["native_emotes"] is False
    assert metadata["presentation"]["native_lobby"] is False
    assert {font["path"] for font in metadata["presentation"]["fonts"].values()} == {
        "font/cjk/lanapixel.fnt"
    }
    selected = generate("j835", tmp_path / "output")
    assert selected["signatures"]
    build = tmp_path / "build"
    subprocess.run(
        [
            "cmake",
            "-S",
            str(ROOT),
            "-B",
            str(build),
            "-DISAAC_LAN_BACKEND=j835",
            "-DISAAC_LAN_BUILD_ENGINE=OFF",
            "-DBUILD_TESTING=OFF",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert build_profile(build) == selected


def test_metadata_alone_cannot_enable_an_incomplete_native_backend(tmp_path):
    metadata = backend_metadata("j835")
    metadata["backend"] = "fixture"
    directory = tmp_path / "src/engine/versions/fixture"
    directory.mkdir(parents=True)
    (directory / "profile.json").write_text(json.dumps(metadata))
    with pytest.raises(ValueError, match="Native backend is not implemented: fixture"):
        source_profile("fixture", root=tmp_path)
    (tmp_path / "CMakeLists.txt").write_text(
        "cmake_minimum_required(VERSION 3.20)\nproject(backend_fixture NONE)\n"
        f'include("{ROOT / "cmake/Backend.cmake"}")\n'
    )
    build = tmp_path / "build"
    result = subprocess.run(
        ["cmake", "-S", str(tmp_path), "-B", str(build), "-DISAAC_LAN_BACKEND=fixture"],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "Native backend fixture has metadata but no implementation" in result.stderr
    assert not (build / "game-profile.json").exists()


def test_resource_fixtures_match_each_backends_metadata():
    # Execute the Lua fixture and compare values; the fixture's version branch
    # must not drift from the metadata that the native bridge actually exports.
    for backend, vanilla in [("j460", False), ("j835", True)]:
        script = f'''
local r = dofile("{ROOT}/tests/fixtures/presentation_assets.lua")({str(vanilla).lower()})
print(tostring(r.native_lobby))
for _,name in ipairs({{"small", "normal", "heading"}}) do
    print(r.fonts[name].path)
    print(r.fonts[name].scale)
end
'''
        result = subprocess.check_output(["lua5.3", "-"], input=script, text=True).splitlines()
        metadata = backend_metadata(backend)["presentation"]
        assert result[0] == str(metadata["native_lobby"]).lower()
        for i, name in enumerate(("small", "normal", "heading")):
            assert result[1 + 2 * i] == metadata["fonts"][name]["path"]
            assert float(result[2 + 2 * i]) == metadata["fonts"][name]["scale"]
