"""Prepare the native update payload from an already validated release ZIP."""

import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile

if __package__:
    from .game_profiles import (
        DEFAULT_BACKEND,
        LEGACY_BACKENDS,
        LEGACY_BUILDS,
        bundle_backends,
        validate,
    )
else:
    from game_profiles import (
        DEFAULT_BACKEND,
        LEGACY_BACKENDS,
        LEGACY_BUILDS,
        bundle_backends,
        validate,
    )

ROOT = Path(__file__).resolve().parents[1]
_HEADER = (ROOT / "src/core/extension_package.h").read_text(encoding="utf-8")
LOADER_ABI = int(re.search(r"unsigned loaderABI = (\d+);", _HEADER)[1])


def constant(name):
    return re.search(rf'char {name}\[\] = "([^"]+)";', _HEADER)[1]


def update_files(zipped, prefix, payload, edition=None):
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
    fields = (
        f"version={payload['extension_version']}\n"
        f"game_build={payload['game_build']}\n"
        f"loader_abi={LOADER_ABI}\n"
        f"sha256={digest}\n"
    )
    files = {
        constant("payloadFile"): dll,
        constant("manifestFile"): (constant("manifestMagic") + "\n" + fields).encode("ascii"),
    }
    if edition is not None:
        raw = zipped.read(prefix + "game-profile.json")
        if hashlib.sha256(raw).hexdigest() != payload["linux_files"]["game-profile.json"]:
            raise ValueError("Update game profile differs from the release manifest")
        profile = validate(json.loads(raw))
        build, rva = profile["game_build"], profile["version_rva"]
        if (
            profile["backend"] != payload["backend"]
            or build != payload["game_build"]
            or not re.fullmatch(r"[0-9]+(?:\.[0-9]+)+b?\.J[0-9]+", build)
            or rva + len(build) + 1 > profile["minimum_image_size"]
        ):
            raise ValueError("Invalid update game build marker")
        files[constant("buildManifestFile")] = (
            f"{constant('buildManifestMagic')}\n{fields}backend={edition}\nversion_rva={rva}\n"
        ).encode("ascii")
    return files


def prepare_update(archive, content):
    root = content / constant("workshopDirectory")
    updates = {}
    with ZipFile(archive) as zipped:
        prefix = archive.stem + "/"
        index = json.loads(zipped.read(prefix + "payload.json"))
        if index.get("format") == 3:
            for backend in bundle_backends(index, allow_legacy=True):
                directory = prefix + f"backends/{backend}/"
                payload = json.loads(zipped.read(directory + "payload.json"))
                if payload.get("backend") != backend:
                    raise ValueError("Update backend differs from release manifest")
                edition = LEGACY_BACKENDS.get(backend, backend)
                files = update_files(zipped, directory, payload, edition)
                updates[root / edition] = files
                # Older loaders can only address their original build or the flat update.
                build = payload["game_build"]
                if LEGACY_BUILDS.get(build) == edition:
                    updates[root if edition == DEFAULT_BACKEND else root / build] = {
                        name: data
                        for name, data in files.items()
                        if name != constant("buildManifestFile")
                    }
        elif "loader_abi" in index:
            updates[root] = update_files(zipped, prefix, index)
    if updates:
        root.mkdir(parents=True)
    for destination, files in updates.items():
        if destination != root:
            destination.mkdir()
        for name, data in files.items():
            (destination / name).write_bytes(data)
