#!/usr/bin/env python3
"""Read-only executable audit. Never patches files or copies game code to reports.

Symbol hints are supplied from a separate, explicitly selected REPENTOGON checkout.
A unique signature match is a candidate, not proof of ABI/semantic compatibility.
"""

import argparse
import json
from pathlib import Path
import re
import struct

from native_image import NativeImage


def pattern_regex(pattern):
    pattern = pattern.replace("(", "").replace(")", "")
    if not re.fullmatch(r"(?:[0-9a-fA-F]{2}|\?\?)+", pattern):
        raise ValueError("Unsupported signature syntax")
    return re.compile(
        b"".join(
            b"." if s == "??" else re.escape(bytes.fromhex(s)) for s in re.findall(r"..", pattern)
        ),
        re.DOTALL,
    )


def inspect(executable, reference):
    functions = reference / "libzhl/functions"
    filenames = sorted(functions.glob("*.zhl"))
    if not filenames:
        raise ValueError("Reference checkout contains no libzhl/functions/*.zhl files")
    image = NativeImage(executable)
    pe = image.pe
    result = {
        **image.describe(),
        "image_base": hex(pe.OPTIONAL_HEADER.ImageBase),
        "image_size": hex(pe.OPTIONAL_HEADER.SizeOfImage),
        "machine": "x86",
        "symbols": {},
        "imports": {},
        "note": "Static candidates only; do not enable engine writes based on this report.",
    }
    for imported in getattr(pe, "DIRECTORY_ENTRY_IMPORT", ()):
        result["imports"][imported.dll.decode()] = [
            {
                "name": entry.name.decode() if entry.name else f"ordinal:{entry.ordinal}",
                "iat_rva": hex(entry.address - pe.OPTIONAL_HEADER.ImageBase),
            }
            for entry in imported.imports
        ]
    for filename in filenames:
        source = filename.read_text()
        source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
        source = re.sub(r"//[^\n]*", "", source)
        for match in re.finditer(r'"([0-9a-fA-F?()]+)":\s*([^;]+);', source):
            pattern, declaration = match.groups()
            declaration = " ".join(declaration.split())
            symbol = re.search(r"([\w:]+)\s*\(", declaration)
            if not symbol and not declaration.startswith("reference "):
                continue
            name = symbol.group(1) if symbol else declaration.split()[-1].lstrip("*")
            if symbol and "::" not in name:
                prefix = source[: match.start()]
                classes = list(re.finditer(r"\bstruct\s+(\w+)[^\n]*\{", prefix))
                if not classes or "__vtable" not in prefix[classes[-1].start() :]:
                    continue
                name = classes[-1].group(1) + "::" + name
            try:
                pattern_regex(pattern)  # Reject reference syntax we do not interpret.
                addresses = image.scan(pattern.replace("(", "").replace(")", ""))
            except ValueError:
                continue
            entry = {
                "source": filename.name,
                "declaration": declaration,
                "rvas": [hex(a) for a in addresses],
                "status": "unique_candidate" if len(addresses) == 1 else "unresolved",
            }
            if "(" in pattern:
                # A repeated pattern can refer to different globals. Preserve
                # the instruction-to-target relationship for every occurrence.
                capture = re.fullmatch(r"([^()]+)\((\?{8})\)([^()]*)", pattern)
                if capture:
                    capture_offset = len(capture[1]) // 2
                    references = []
                    for address in addresses:
                        value = struct.unpack("<I", pe.get_data(address + capture_offset, 4))[0]
                        rva = value - pe.OPTIONAL_HEADER.ImageBase
                        references.append(
                            {
                                "instruction_rva": hex(address),
                                "target_rva": hex(rva),
                                "in_image": 0 <= rva < pe.OPTIONAL_HEADER.SizeOfImage,
                            }
                        )
                    entry["references"] = references
                    if len(references) == 1 and references[0]["in_image"]:
                        entry["referenced_rva"] = references[0]["target_rva"]
                else:
                    entry["capture_status"] = "unsupported"
            if name in result["symbols"]:
                # Preserve every overload and its declaration; sharing a name
                # does not establish a common address or calling convention.
                previous = result["symbols"][name]
                overloads = previous.get("overloads", [previous]) + [entry]
                result["symbols"][name] = {"status": "overloaded", "overloads": overloads}
            else:
                result["symbols"][name] = entry
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = inspect(args.executable, args.reference)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as output:
        output.write(json.dumps(result, indent=2) + "\n")
    resolved = sum(s["status"] == "unique_candidate" for s in result["symbols"].values())
    print(f"{result['sha256']}: {resolved}/{len(result['symbols'])} unique candidates")
    for name in ("g_Game", "Game::Update", "Room::constructor", "Room::Init", "Level::ChangeRoom"):
        print(name, result["symbols"].get(name))


if __name__ == "__main__":
    main()
