"""Prepare the native update payload from an already validated release ZIP."""

import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
_HEADER = (ROOT / "src/core/extension_package.h").read_text(encoding="utf-8")
LOADER_ABI = int(re.search(r"unsigned loaderABI = (\d+);", _HEADER)[1])


def constant(name):
    return re.search(rf'char {name}\[\] = "([^"]+)";', _HEADER)[1]


def prepare_update(archive, content):
    with ZipFile(archive) as zipped:
        prefix = archive.stem + "/"
        payload = json.loads(zipped.read(prefix + "payload.json"))
        # Older releases remain publishable, with their original manual installer.
        if "loader_abi" not in payload:
            return
        if type(payload["loader_abi"]) is not int or payload["loader_abi"] != LOADER_ABI:
            raise ValueError("Unsupported release loader ABI")
        dll = zipped.read(prefix + constant("payloadFile"))
        digest = hashlib.sha256(dll).hexdigest()
        if digest != payload["files"][constant("payloadFile")]:
            raise ValueError("Update DLL differs from the release manifest")
        version = payload["extension_version"]
        if not re.fullmatch(
            r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version
        ) or any(int(part) > 0xFFFFFFFF for part in version.split(".")):
            raise ValueError("Invalid update version")
        if not re.fullmatch(r"[0-9.J]+", payload["game_build"]):
            raise ValueError("Invalid update game build")
        destination = content / constant("workshopDirectory")
        destination.mkdir()
        (destination / constant("payloadFile")).write_bytes(dll)
        (destination / constant("manifestFile")).write_text(
            f"{constant('manifestMagic')}\n"
            f"version={payload['extension_version']}\n"
            f"game_build={payload['game_build']}\n"
            f"loader_abi={LOADER_ABI}\n"
            f"sha256={digest}\n",
            encoding="ascii",
            newline="\n",
        )
