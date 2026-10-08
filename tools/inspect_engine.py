#!/usr/bin/env python3
"""Read-only executable audit. Never patches files or copies game code to reports.

Symbol hints are supplied from a separate, explicitly selected REPENTOGON checkout.
A unique signature match is a candidate, not proof of ABI/semantic compatibility.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

import pefile


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
    binary = executable.read_bytes()
    pe = pefile.PE(data=binary)
    if pe.FILE_HEADER.Machine != 0x14C:
        raise ValueError("Expected a 32-bit x86 executable")
    sections = []
    for section in pe.sections:
        if section.Characteristics & 0x20000000:
            sections.append((section.VirtualAddress, section.get_data()))
    result = {
        "sha256": hashlib.sha256(binary).hexdigest(),
        "image_base": hex(pe.OPTIONAL_HEADER.ImageBase),
        "image_size": hex(pe.OPTIONAL_HEADER.SizeOfImage),
        "machine": "x86",
        "symbols": {},
        "imports": {},
        "note": "Static candidates only; do not enable engine writes based on this report.",
    }
    for imported in pe.DIRECTORY_ENTRY_IMPORT:
        result["imports"][imported.dll.decode()] = [
            {
                "name": entry.name.decode() if entry.name else f"ordinal:{entry.ordinal}",
                "iat_rva": hex(entry.address - pe.OPTIONAL_HEADER.ImageBase),
            }
            for entry in imported.imports
        ]
    for filename in ("Game", "Room", "Level", "EntityList", "PlayerManager", "Manager"):
        source = (reference / "libzhl/functions" / (filename + ".zhl")).read_text()
        source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
        for match in re.finditer(r'"([0-9a-fA-F?()]+)":\s*([^;]+);', source):
            pattern, declaration = match.groups()
            declaration = " ".join(declaration.split())
            symbol = re.search(r"(\w+::\w+)\(", declaration)
            if not symbol and not declaration.startswith("reference "):
                continue
            name = symbol.group(1) if symbol else declaration.split()[-1].lstrip("*")
            try:
                expression = pattern_regex(pattern)
            except ValueError:
                continue
            addresses = [
                rva + m.start() for rva, code in sections for m in expression.finditer(code)
            ]
            entry = {
                "declaration": declaration,
                "rvas": [hex(a) for a in addresses],
                "status": "unique_candidate" if len(addresses) == 1 else "unresolved",
            }
            if len(addresses) == 1 and "(" in pattern:
                capture_offset = pattern.index("(") // 2
                value = struct.unpack("<I", pe.get_data(addresses[0] + capture_offset, 4))[0]
                entry["referenced_rva"] = hex(value - pe.OPTIONAL_HEADER.ImageBase)
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
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    resolved = sum(s["status"] == "unique_candidate" for s in result["symbols"].values())
    print(f"{result['sha256']}: {resolved}/{len(result['symbols'])} unique candidates")
    for name in ("g_Game", "Game::Update", "Room::constructor", "Room::Init", "Level::ChangeRoom"):
        print(name, result["symbols"].get(name))


if __name__ == "__main__":
    main()
