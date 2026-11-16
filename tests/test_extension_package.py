"""Release-to-Workshop payload provenance and loader contract boundaries."""

import hashlib
import json
from zipfile import ZipFile

import pytest

import extension_package as package
import workshop_release


def archive(tmp_path, **changes):
    path = tmp_path / "Isaac-LAN-v0.6.4-windows-x86.zip"
    dll = b"exact release DLL bytes"
    payload = {
        "extension_version": "0.6.4",
        "game_build": "1.9.7.17.J460",
        "loader_abi": package.LOADER_ABI,
        "files": {"isaac_lan_probe.dll": hashlib.sha256(dll).hexdigest()},
    }
    payload.update(changes)
    if payload["loader_abi"] is None:
        del payload["loader_abi"]
    with ZipFile(path, "w") as zipped:
        zipped.writestr(path.stem + "/payload.json", json.dumps(payload))
        zipped.writestr(path.stem + "/isaac_lan_probe.dll", dll)
    return path, dll


def test_payload_is_exact_release_bytes_and_contract(tmp_path):
    path, dll = archive(tmp_path)
    package.prepare_update(path, tmp_path)
    update = tmp_path / package.constant("workshopDirectory")
    assert (update / package.constant("payloadFile")).read_bytes() == dll
    assert (update / package.constant("manifestFile")).read_bytes() == (
        f"{package.constant('manifestMagic')}\nversion=0.6.4\n"
        f"game_build=1.9.7.17.J460\nloader_abi={package.LOADER_ABI}\n"
        f"sha256={hashlib.sha256(dll).hexdigest()}\n"
    ).encode("ascii")
    assert workshop_release.ITEM_ID == package.constant("workshopItem")


def test_legacy_release_keeps_manual_installation(tmp_path):
    path, _ = archive(tmp_path, loader_abi=None)
    package.prepare_update(path, tmp_path)
    assert not (tmp_path / package.constant("workshopDirectory")).exists()


@pytest.mark.parametrize("abi", [0, 2, True, "1"])
def test_incompatible_loader_contract_is_rejected_before_writing(tmp_path, abi):
    path, _ = archive(tmp_path, loader_abi=abi)
    with pytest.raises(ValueError, match="loader ABI"):
        package.prepare_update(path, tmp_path)
    assert not (tmp_path / package.constant("workshopDirectory")).exists()


@pytest.mark.parametrize(
    "changes",
    [
        {"extension_version": "0.6.4\nsha256=bad"},
        {"extension_version": "0.06.4"},
        {"extension_version": "4294967296.0.0"},
        {"game_build": "../escape"},
        {"files": {"isaac_lan_probe.dll": "0" * 64}},
    ],
)
def test_malformed_or_tampered_payload_is_not_prepared(tmp_path, changes):
    path, _ = archive(tmp_path, **changes)
    with pytest.raises(ValueError):
        package.prepare_update(path, tmp_path)
    assert not (tmp_path / package.constant("workshopDirectory")).exists()
