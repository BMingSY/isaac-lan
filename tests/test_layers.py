"""Check executable module inventory and the portable layer dependency boundaries."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def test_embedded_inventory_covers_every_component_once():
    bridge = ROOT / "src/bridge"
    names = (bridge / "modules.txt").read_text().splitlines()
    assert len(names) == len(set(names))
    assert all((bridge / (name + ".lua")).is_file() for name in names)
    standalone = {"app/main", "app/world", "presentation/menu", "presentation/prediction"}
    actual = {str(path.relative_to(bridge).with_suffix("")) for path in bridge.rglob("*.lua")}
    assert set(names) | standalone == actual


def test_transport_has_no_game_or_compatibility_dependency():
    for path in (ROOT / "src/net").rglob("*"):
        if path.suffix not in (".h", ".cpp"):
            continue
        includes = re.findall(r'^#include "([^"]+)"', path.read_text(), re.MULTILINE)
        assert all(name.startswith(("net/", "core/")) for name in includes), (path, includes)


def test_native_compatibility_policies_remain_portable():
    for path in (ROOT / "src/compat").rglob("*"):
        if path.suffix not in (".h", ".cpp"):
            continue
        source = path.read_text()
        assert not re.search(r"windows\.h|reinterpret_cast|lua_State|MH_CreateHook", source)
        includes = re.findall(r'^#include "([^"]+)"', source, re.MULTILINE)
        assert all(name.startswith("compat/") for name in includes), (path, includes)


def test_audited_addresses_and_startup_signatures_share_one_catalog():
    backend = ROOT / "src/engine/versions/j460"
    names = set(re.findall(r"std::uint32_t (\w+) =", (backend / "entrypoints.h").read_text()))
    signatures = (backend / "signatures.inc").read_text()
    entries = re.findall(r"\{j460::entry::(\w+),", signatures)
    assert entries and len(entries) == len(set(entries))
    assert set(entries) <= names
    assert not re.search(r'\{0x[0-9a-f]+,\s*"', signatures)


def test_runtime_and_presentation_do_not_implement_game_backends():
    for layer in ("app", "runtime", "presentation"):
        for path in (ROOT / "src" / layer).rglob("*"):
            if path.suffix not in (".h", ".cpp"):
                continue
            source = path.read_text()
            assert not re.search(r"engine/versions/|j460::|MH_CreateHook|MH_EnableHook", source), (
                path
            )


def test_core_dependencies_stay_portable():
    for path in (ROOT / "src/core").rglob("*"):
        if path.suffix not in (".h", ".cpp"):
            continue
        source = path.read_text()
        assert not re.search(r"windows\.h|MinHook|lua_State|engine/versions/", source), path
        includes = re.findall(r'^#include "([^"]+)"', source, re.MULTILINE)
        assert all(
            name.startswith("core/") or name in {"net/protocol.h", "miniz.h"} for name in includes
        ), (path, includes)


def test_lua_components_only_reference_known_modules():
    bridge = ROOT / "src/bridge"
    names = set((bridge / "modules.txt").read_text().splitlines())
    for path in bridge.rglob("*.lua"):
        source = path.read_text()
        for name in re.findall(r'(?:modules|_IsaacLanModules)\["([^"]+)"\]', source):
            assert name in names, (path, name)
        if path.relative_to(bridge).parts[0] in {"sync", "compat", "runtime", "presentation"}:
            assert not re.search(r'(?:modules|_IsaacLanModules)\["app/', source), path


def test_native_and_fixture_phase_names_match():
    source = (ROOT / "src/net/protocol.h").read_text()
    enum = re.search(r"enum class Phase \{(.*?)\};", source, re.DOTALL)[1]
    expected = dict(re.findall(r"(\w+)\s*=\s*(\d+)", enum))
    fixture = (ROOT / "tests/fixtures/net_phases.lua").read_text()
    assert dict(re.findall(r"(\w+)\s*=\s*(\d+)", fixture)) == expected


def test_repository_document_links_resolve():
    for path in [ROOT / "AGENTS.md", ROOT / "README.md", *(ROOT / "docs").rglob("*.md")]:
        for target in re.findall(
            r"https://github.com/BMingSY/isaac-lan/(?:blob|tree)/main/([^\s)#]+)",
            path.read_text(),
        ):
            assert (ROOT / target).exists(), (path, target)
