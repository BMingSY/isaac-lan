"""Prepare the native update payload from an already validated release ZIP."""

import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile

if __package__:
    from .game_profiles import DEFAULT_BACKEND, bundle_backends
else:
    from game_profiles import DEFAULT_BACKEND, bundle_backends

ROOT = Path(__file__).resolve().parents[1]
_HEADER = (ROOT / "src/core/extension_package.h").read_text(encoding="utf-8")
LOADER_ABI = int(re.search(r"unsigned loaderABI = (\d+);", _HEADER)[1])


def constant(name):
    return re.search(rf'char {name}\[\] = "([^"]+)";', _HEADER)[1]


def update_files(zipped, prefix, payload):
    if type(payload["loader_abi"]) is not int or payload["loader_abi"] != LOADER_ABI:
        raise ValueError("Unsupported release loader ABI")
    dll = zipped.read(prefix + constant("payloadFile"))
    digest = hashlib.sha256(dll).hexdigest()
    if digest != payload["files"][constant("payloadFile")]:
        raise ValueError("Update DLL differs from the release manifest")
    version = payload["extension_version"]
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version) or any(
        int(part) > 0xFFFFFFFF for part in version.split(".")
    ):
        raise ValueError("Invalid update version")
    if not re.fullmatch(r"[0-9][0-9.bJ]*", payload["game_build"]):
        raise ValueError("Invalid update game build")
    manifest = (
        f"{constant('manifestMagic')}\n"
        f"version={payload['extension_version']}\n"
        f"game_build={payload['game_build']}\n"
        f"loader_abi={LOADER_ABI}\n"
        f"sha256={digest}\n"
    )
    return dll, manifest


def prepare_update(archive, content):
    root = content / constant("workshopDirectory")
    updates = {}
    with ZipFile(archive) as zipped:
        prefix = archive.stem + "/"
        index = json.loads(zipped.read(prefix + "payload.json"))
        if index.get("format") == 2:
            for backend in bundle_backends(index):
                directory = prefix + f"backends/{backend}/"
                payload = json.loads(zipped.read(directory + "payload.json"))
                if payload.get("backend") != backend:
                    raise ValueError("Update backend differs from release manifest")
                files = update_files(zipped, directory, payload)
                # Existing Repentance+ loaders read the root of the Workshop update.
                destination = root if backend == DEFAULT_BACKEND else root / payload["game_build"]
                updates[destination] = files
        elif "loader_abi" in index:
            updates[root] = update_files(zipped, prefix, index)
    for destination, (dll, manifest) in updates.items():
        destination.mkdir(parents=True)
        (destination / constant("payloadFile")).write_bytes(dll)
        (destination / constant("manifestFile")).write_text(
            manifest, encoding="ascii", newline="\n"
        )
