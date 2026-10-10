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
    for path in (ROOT / "src/compat").rglob("*.h"):
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
