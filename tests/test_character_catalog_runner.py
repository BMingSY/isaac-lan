import sys
from pathlib import Path
import xml.etree.ElementTree as ET

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from run_character_catalog import peer_evidence, validate_labs  # noqa: E402


def make_lab(root, name):
    lab = root / name
    (lab / "game").mkdir(parents=True)
    (lab / ".isaac-lan-lab").write_text("owned")
    (lab / "game/isaac-ng.exe").write_bytes(b"fixture")
    return lab


@pytest.mark.parametrize("reserved", ["host-001", "client-001"])
def test_manual_labs_and_symlinks_are_refused(tmp_path, reserved):
    labs = [make_lab(tmp_path, name) for name in [reserved, "a", "b", "c"]]
    with pytest.raises(ValueError, match="manual games"):
        validate_labs(labs)
    alias = tmp_path / "alias"
    alias.symlink_to(labs[0], target_is_directory=True)
    with pytest.raises(ValueError, match="manual games"):
        validate_labs([alias, *labs[1:]])


def test_character_fixture_uses_native_registration_without_fixed_ids():
    root = ROOT / "tests/fixtures/registered_characters"
    players = ET.parse(root / "content/players.xml").getroot().findall("player")
    assert len(players) == 4 and all("id" not in player.attrib for player in players)
    assert players[1].get("bSkinParent") == players[0].get("name")
    assert players[2].get("achievement") == "475"
    assert players[3].get("hidden") == "true"
    assert not (root / "main.lua").exists()


def test_completion_does_not_accept_only_the_terminal_banner():
    text = "LAN_NETWORK PASS native character catalog\nREGISTERED ids=701,704,709,713\n"
    assert not peer_evidence(text, 3)["passed"]
    prefix = "CHARACTER_CATALOG case=four-tainted "
    text += "\n".join(
        prefix + marker
        for marker in [
            "MENU_SELECTED id=704",
            "PASS menu_cleanup=true",
            "REPLICA_TYPES_VERIFIED tick=120",
        ]
    )
    assert peer_evidence(text, 3)["passed"]
    assert not peer_evidence(text + "\nLAN_NETWORK FAILED later error", 3)["passed"]
