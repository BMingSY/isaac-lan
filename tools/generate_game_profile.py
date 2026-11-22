"""Generate the selected C++ profile and the matching build/package metadata."""

import argparse
import json
from pathlib import Path
from game_profiles import RELEASE_BACKENDS, backend_metadata, loader_versions, source_profile


def generate(backend, output):
    profile = source_profile(backend)
    output.mkdir(parents=True, exist_ok=True)
    (output / "game-profile.json").write_text(json.dumps(profile, indent=2) + "\n")
    lines = [
        "#pragma once",
        '#include "engine/profile.h"',
        "namespace isaac::engine {",
        "namespace {",
        "constexpr RequiredSection selectedSections[] = {",
    ]
    for section in profile["sections"]:
        lines.append(
            "    {" + ", ".join(hex(section[k]) for k in ("start", "size", "flags")) + "},"
        )
    lines += ["};", "constexpr Signature selectedSignatures[] = {"]
    for signature in profile["signatures"]:
        data = ", ".join(hex(value) for value in bytes.fromhex(signature["bytes"]))
        lines.append(
            f"    {{{hex(signature['rva'])}, {json.dumps(signature['name'])}, "
            f"{{{data}}}, {hex(signature['mask'])}}},"
        )
    lines += ["};", "constexpr Profile selectedProfile{"]
    for key in ("backend", "game_build", "game_name", "documents_directory", "lua_module"):
        lines.append("    " + json.dumps(profile[key]) + ",")
    lines += [
        f"    {hex(profile['version_rva'])}, {hex(profile['minimum_image_size'])},",
        "    selectedSections, selectedSignatures,",
        "    {" + str(profile["capabilities"]["native_emotes"]).lower() + "},",
        "    {" + str(profile["presentation"]["native_lobby"]).lower() + ",",
    ]
    for name in ("small", "normal", "heading"):
        font = profile["presentation"]["fonts"][name]
        lines.append(f"        {{{json.dumps(font['path'])}, {float(font['scale'])}f}},")
    lines += [
        "    }",
        "};",
        "} // namespace",
        "} // namespace isaac::engine",
        "",
    ]
    (output / "selected_game_profile.h").write_text("\n".join(lines))
    versions = [
        "#pragma once",
        '#include "engine/game_version.h"',
        "namespace isaac::engine {",
        "inline constexpr GameVersion supportedGameVersions[] = {",
    ]
    targets = loader_versions(backend_metadata(edition) for edition in RELEASE_BACKENDS)
    (output / "loader-versions.json").write_text(json.dumps(targets, indent=2) + "\n")
    for name, metadata in targets.items():
        versions.append(
            f'    {{"{name}", {json.dumps(metadata["game_build"])}, {hex(metadata["version_rva"])} }},'
        )
    versions += ["};", "} // namespace isaac::engine", ""]
    (output / "supported_game_versions.h").write_text("\n".join(versions))
    return profile


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    generate(args.backend, args.output)
