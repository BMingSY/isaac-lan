"""Version metadata shared by build, packaging and isolated test tools."""

import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BACKEND = "j510"


def validate(profile):
    if profile.get("format") != 1 or not re.fullmatch(r"[a-z0-9_]+", profile.get("backend", "")):
        raise ValueError("Invalid game backend profile")
    for name in ("game_build", "game_name", "documents_directory", "lua_module"):
        value = profile.get(name)
        if not isinstance(value, str) or not value or any(ord(c) < 32 for c in value):
            raise ValueError(f"Invalid game profile field: {name}")
    for name in ("documents_directory", "lua_module"):
        if any(c in profile[name] for c in "/\\:") or profile[name] in (".", ".."):
            raise ValueError(f"Game profile field must be a filename: {name}")
    for name in ("version_rva", "minimum_image_size"):
        if type(profile.get(name)) is not int or not 0 < profile[name] <= 0xFFFFFFFF:
            raise ValueError(f"Invalid game profile address: {name}")
    if not profile.get("sections"):
        raise ValueError("Game profile requires PE sections")
    for section in profile["sections"]:
        if any(
            type(section.get(k)) is not int or not 0 < section[k] <= 0xFFFFFFFF
            for k in ("start", "size", "flags")
        ):
            raise ValueError("Invalid game profile section")
        if section["start"] + section["size"] > profile["minimum_image_size"]:
            raise ValueError("Game profile section exceeds image size")
    if type(profile.get("capabilities", {}).get("native_emotes")) is not bool:
        raise ValueError("Missing native emote capability")
    # Older lab snapshots do not carry presentation metadata. They remain
    # readable for profile protection; configuring a backend requires it below.
    if "presentation" in profile:
        presentation = profile["presentation"]
        if not isinstance(presentation, dict) or type(presentation.get("native_lobby")) is not bool:
            raise ValueError("Invalid native lobby resource capability")
        fonts = presentation.get("fonts")
        if not isinstance(fonts, dict) or set(fonts) != {"small", "normal", "heading"}:
            raise ValueError("Three named menu fonts are required")
        for font in fonts.values():
            if not isinstance(font, dict):
                raise ValueError("Invalid menu font")
            path, scale = font.get("path"), font.get("scale")
            if (
                not isinstance(path, str)
                or not path.startswith("font/")
                or not path.endswith(".fnt")
                or any(c in path for c in "\\:")
                or any(ord(c) < 32 for c in path)
                or any(part in {"", ".", ".."} for part in path.split("/"))
                or type(scale) not in (int, float)
                or not math.isfinite(scale)
                or not 0 < scale <= 4
            ):
                raise ValueError("Invalid menu font path or scale")
    return profile


def backend_metadata(backend=DEFAULT_BACKEND, *, root=ROOT):
    if not re.fullmatch(r"[a-z0-9_]+", backend):
        raise ValueError("Invalid backend identifier")
    directory = root / "src/engine/versions" / backend
    profile = validate(json.loads((directory / "profile.json").read_text()))
    if profile["backend"] != backend:
        raise ValueError("Backend directory and profile differ")
    return profile


def source_profile(backend=DEFAULT_BACKEND, *, root=ROOT):
    profile = backend_metadata(backend, root=root)
    directory = root / "src/engine/versions" / backend
    if not (directory / "sources.cmake").is_file():
        raise ValueError(f"Native backend is not implemented: {backend}")
    if "presentation" not in profile:
        raise ValueError("Backend requires presentation resource metadata")
    header = (directory / "entrypoints.h").read_text()
    addresses = dict(re.findall(r"std::uint32_t (\w+) = (0x[0-9a-f]+);", header))
    source = (directory / "signatures.inc").read_text()
    entries = re.findall(
        rf'\{{{re.escape(backend)}::entry::(\w+),\s*"([^"\n]+)",\s*\{{([^}}]+)\}},\s*(0x[0-9a-f]+)\}}',
        source,
    )
    if not entries or len(entries) != source.count("::entry::"):
        raise ValueError("Incomplete native signature catalog")
    signatures = []
    names = set()
    for entry, name, values, mask in entries:
        data = bytes(int(value.strip(), 0) for value in values.split(","))
        if (
            entry not in addresses
            or entry in names
            or len(data) != 16
            or not 0 < int(mask, 16) <= 0xFFFF
        ):
            raise ValueError(f"Invalid native signature: {entry}")
        names.add(entry)
        signatures.append(
            {
                "name": name,
                "rva": int(addresses[entry], 16),
                "bytes": data.hex(),
                "mask": int(mask, 16),
            }
        )
    profile["signatures"] = signatures
    return profile


def build_profile(build):
    """Use the configured build's snapshot, never the source tree's default."""
    return validate(json.loads((Path(build) / "game-profile.json").read_text()))


def lab_profile(lab):
    path = Path(lab) / "game-profile.json"
    if not path.is_file():
        raise ValueError("Missing game-profile.json; prepare this lab with a supported game build")
    return validate(json.loads(path.read_text()))


def release_name(tag, backend):
    # Keep the established Repentance+ download name for existing clients.
    suffix = {"j510": "", "j835": "-j835"}[backend]
    return f"Isaac-LAN-{tag}{suffix}-windows-x86"


def profile_directory(lab):
    lab = Path(lab)
    # Historical Repentance+ logs predate the snapshot. Reading a log path
    # does not qualify its game or save for a new native test.
    directory = (
        lab_profile(lab)["documents_directory"]
        if (lab / "game-profile.json").is_file()
        else "Binding of Isaac Repentance+"
    )
    return lab / "profile/Documents/My Games" / directory
