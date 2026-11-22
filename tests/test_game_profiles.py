"""Exercise version selection through build artifacts, installers and owned labs."""

import copy
import json
from pathlib import Path
import re
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
    profile = generate("repentance_plus", tmp_path)
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


def test_repentance_plus_manager_fields_match_checked_game_instructions(tmp_path):
    signatures = {entry["name"]: entry for entry in source_profile("repentance_plus")["signatures"]}
    source = tmp_path / "manager.cpp"
    lines = [
        '#include "engine/versions/repentance_plus/layout.h"',
        "using namespace isaac::engine::repentance_plus;",
    ]
    for signature, start, field in (
        ("Manager.CharacterConfigVector", 2, "layout::manager::characterConfigs"),
        ("Manager.CharacterConfigVector", 8, "layout::manager::characterConfigs + 4"),
        (
            "Game.Update.focusPauseOption",
            2,
            "layout::manager::options + layout::options::pauseOnFocusLost",
        ),
    ):
        entry = signatures[signature]
        # The game checker must compare all four bytes of the x86 displacement.
        assert (entry["mask"] >> start) & 0xF == 0xF
        offset = int.from_bytes(bytes.fromhex(entry["bytes"])[start : start + 4], "little")
        lines.append(f"static_assert({field} == {offset:#x});")
    source.write_text("\n".join(lines))
    subprocess.run(
        ["c++", "-std=c++20", "-fsyntax-only", "-I", str(ROOT / "src"), str(source)], check=True
    )


@pytest.mark.parametrize("backend", ["repentance", "repentance_plus"])
def test_lab_observations_read_the_selected_backend_layout(backend, tmp_path):
    directory = ROOT / "src/engine/versions" / backend
    values = dict(
        re.findall(
            r"^    (\w+) = (0x[0-9a-f]+)$",
            (directory / "lab_observations.psd1").read_text(),
            re.MULTILINE,
        )
    )
    native_fields = {
        "manager": "globals::manager",
        "menus": "globals::menuManager",
        "game": "globals::game",
        "dialogs": "layout::manager::menuInputBlock",
        "page": "layout::menuManager::page",
        "hud": "layout::game::hud",
        "history": "layout::hud::history",
        "partBytes": "layout::playerHud::size",
        "controller": "layout::player::controller",
        "visible": "layout::entity::visible",
        "stageTransition": "layout::game::stageTransition",
        "frame": "layout::game::frame",
        "room": "layout::game::roomIndex",
        "color": "layout::game::currentColor",
    }
    source = tmp_path / "observations.cpp"
    source.write_text(
        f'#include "engine/versions/{backend}/entrypoints.h"\n'
        f'#include "engine/versions/{backend}/layout.h"\n'
        f"using namespace isaac::engine::{backend};\n"
        + "".join(
            f'static_assert({field} == {values[key]}, "{key}");\n'
            for key, field in native_fields.items()
        )
    )
    subprocess.run(
        ["c++", "-std=c++20", "-fsyntax-only", "-I", str(ROOT / "src"), str(source)], check=True
    )


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
    # A malformed explicit profile must not fall back to Repentance+.
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
    with pytest.raises(ValueError, match="Unsupported game backend"):
        generate("unimplemented", tmp_path / "out")
    assert not (tmp_path / "out").exists()
    for name in (
        "../repentance_plus",
        "repentance_plus/../repentance_plus",
        "repentance_plus;main",
    ):
        with pytest.raises(ValueError):
            source_profile(name)


@pytest.mark.parametrize(
    "path,scale",
    [
        ("font/../private.fnt", 1),
        ("resources-dlc3.zh/font/../private.fnt", 1),
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


def test_numbered_lab_snapshot_only_reuses_an_exact_supported_build(tmp_path, monkeypatch):
    edition = "repentance_plus"
    snapshot = tmp_path / "game-profile.json"
    profile = backend_metadata(edition)
    supported = "1.9.7.19.J511"
    monkeypatch.setattr("game_profiles.backend_metadata", lambda _: {"game_build": supported})
    monkeypatch.setattr("progress_fixture.backend_metadata", lambda _: {"game_build": supported})
    profile["game_build"] = supported
    profile["backend"] = profile["testing"]["progress_fixture"] = "j511"
    snapshot.write_text(json.dumps(profile))
    assert lab_profile(tmp_path)["backend"] == edition
    assert lab_profile(tmp_path)["testing"]["progress_fixture"] == edition
    profile["backend"] = profile["testing"]["progress_fixture"] = "j510"
    profile["game_build"] = "1.9.7.19.J510"
    snapshot.write_text(json.dumps(profile))
    assert lab_profile(tmp_path)["backend"] == "j510"
    (tmp_path / ".isaac-lan-lab").touch()
    with pytest.raises(ValueError, match="No audited progress fixture"):
        prepare(tmp_path, host=True)
    profile["backend"] = profile["testing"]["progress_fixture"] = edition
    snapshot.write_text(json.dumps(profile))
    with pytest.raises(ValueError, match="No audited progress fixture"):
        prepare(tmp_path, host=True)


def test_repentance_backend_generates_original_capabilities(tmp_path):
    metadata = backend_metadata("repentance")
    assert metadata["game_name"] == "Repentance"
    assert metadata["documents_directory"] == "Binding of Isaac Repentance"
    assert metadata["capabilities"]["native_emotes"] is False
    assert metadata["presentation"]["native_lobby"] is False
    assert {font["path"] for font in metadata["presentation"]["fonts"].values()} == {
        "resources-dlc3.zh/font/TeamMeatFontExtended10.fnt",
        "resources-dlc3.zh/font/TeamMeatFontExtended12.fnt",
        "resources-dlc3.zh/font/TeamMeatFontExtended16Bold.fnt",
    }
    selected = generate("repentance", tmp_path / "output")
    assert selected["signatures"]
    build = tmp_path / "build"
    subprocess.run(
        [
            "cmake",
            "-S",
            str(ROOT),
            "-B",
            str(build),
            "-DISAAC_LAN_BACKEND=repentance",
            "-DISAAC_LAN_BUILD_ENGINE=OFF",
            "-DBUILD_TESTING=OFF",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert build_profile(build) == selected


def test_metadata_alone_cannot_enable_an_incomplete_native_backend(tmp_path):
    metadata = backend_metadata("repentance")
    directory = tmp_path / "src/engine/versions/repentance"
    directory.mkdir(parents=True)
    (directory / "profile.json").write_text(json.dumps(metadata))
    with pytest.raises(ValueError, match="Native backend is not implemented: repentance"):
        source_profile("repentance", root=tmp_path)
    (tmp_path / "CMakeLists.txt").write_text(
        "cmake_minimum_required(VERSION 3.20)\nproject(backend_fixture NONE)\n"
        f'include("{ROOT / "cmake/Backend.cmake"}")\n'
    )
    build = tmp_path / "build"
    result = subprocess.run(
        ["cmake", "-S", str(tmp_path), "-B", str(build), "-DISAAC_LAN_BACKEND=repentance"],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "Native backend repentance has metadata but no implementation" in result.stderr
    assert not (build / "game-profile.json").exists()


def test_resource_fixtures_match_each_backends_metadata():
    # Execute the Lua fixture and compare values; the fixture's version branch
    # must not drift from the metadata that the native bridge actually exports.
    for backend, vanilla in [("repentance_plus", False), ("repentance", True)]:
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
