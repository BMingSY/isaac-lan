import hashlib
import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import prepare_lab


@pytest.mark.parametrize("owned,loader", [(True, True), (False, True), (True, False)])
def test_preparation_preserves_only_existing_loader_ownership(tmp_path, monkeypatch, owned, loader):
    source, build, lab = (tmp_path / name for name in ("source", "build", "lab"))
    source.mkdir()
    build.mkdir()
    (source / "isaac-ng.exe").write_bytes(b"game")
    (source / "mods").mkdir()
    (source / "resources").mkdir()
    if loader:
        (source / "winmm.dll").write_bytes(b"loader")
    if owned:
        (source / ".isaac-lan-loader").write_text("Owned isolated LAN automatic loader.\n")
    for name in ("isaac_lan_probe.dll", "isaac_lan_lab.exe"):
        (build / name).write_bytes(b"candidate")
    monkeypatch.setattr(
        sys,
        "argv",
        ["prepare_lab", "--game", str(source), "--build", str(build), "--lab", str(lab)],
    )
    prepare_lab.main()
    marker = lab / "game/.isaac-lan-loader"
    assert marker.exists() == (owned and loader)
    manifest = json.loads((lab / "copied-game-manifest.json").read_text())
    if owned and loader:
        assert marker.read_bytes() == (source / marker.name).read_bytes()
        assert manifest[marker.name] == hashlib.sha256(marker.read_bytes()).hexdigest()
    else:
        assert marker.name not in manifest
    if loader:
        assert (lab / "game/winmm.dll").read_bytes() == (source / "winmm.dll").read_bytes()
