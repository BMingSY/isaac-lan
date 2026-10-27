"""Read-only PE inspection for auditing a new game backend, never for installing hooks."""

from dataclasses import dataclass
import hashlib
from pathlib import Path
import re

import pefile


@dataclass(frozen=True)
class Pattern:
    values: bytes
    masks: bytes
    anchor: bytes
    anchor_offset: int

    @classmethod
    def parse(cls, text):
        text = "".join(text.split()).lower()
        if not text or len(text) % 2 or re.search(r"[^0-9a-f?]", text):
            raise ValueError("Expected byte pairs containing hexadecimal digits or ?")
        values, masks = bytearray(), bytearray()
        for i in range(0, len(text), 2):
            pair = text[i : i + 2]
            values.append(int(pair.replace("?", "0"), 16))
            masks.append(sum(0xF << (4 * (1 - j)) for j, c in enumerate(pair) if c != "?"))
        runs = []
        for i, mask in enumerate(masks):
            if mask != 0xFF:
                continue
            if runs and runs[-1][0] + len(runs[-1][1]) == i:
                runs[-1][1].append(values[i])
            else:
                runs.append((i, bytearray([values[i]])))
        if not runs:
            raise ValueError("A native pattern must contain at least one complete fixed byte")
        offset, anchor = max(runs, key=lambda run: len(run[1]))
        return cls(bytes(values), bytes(masks), bytes(anchor), offset)

    def find(self, data):
        start = 0
        while (at := data.find(self.anchor, start)) >= 0:
            start = at + 1
            begin = at - self.anchor_offset
            if begin < 0 or begin + len(self.values) > len(data):
                continue
            if all(data[begin + i] & mask == self.values[i] for i, mask in enumerate(self.masks)):
                yield begin


class NativeImage:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        try:
            self.pe = pefile.PE(data=self.data)
        except pefile.PEFormatError as error:
            raise ValueError("Invalid PE image") from error
        if self.pe.FILE_HEADER.Machine != 0x14C or self.pe.OPTIONAL_HEADER.Magic != 0x10B:
            raise ValueError("A Windows x86 PE image is required")
        for section in self.pe.sections:
            if (
                section.PointerToRawData + section.SizeOfRawData > len(self.data)
                or section.VirtualAddress + section.Misc_VirtualSize
                > self.pe.OPTIONAL_HEADER.SizeOfImage
            ):
                raise ValueError("PE section exceeds image bounds")

    def scan(self, pattern):
        """Return every executable-section match; ambiguity is never resolved by order."""
        pattern = Pattern.parse(pattern)
        return [
            section.VirtualAddress + offset
            for section in self.pe.sections
            if section.Characteristics & 0x20000000
            for offset in pattern.find(section.get_data()[: section.Misc_VirtualSize])
        ]

    def signature(self, rva, length=16):
        if length != 16:
            raise ValueError("Backend startup signatures contain exactly 16 bytes")
        section = next(
            (
                s
                for s in self.pe.sections
                if s.Characteristics & 0x20000000
                and s.VirtualAddress <= rva
                and rva + length <= s.VirtualAddress + min(s.Misc_VirtualSize, s.SizeOfRawData)
            ),
            None,
        )
        if section is None:
            raise ValueError("Signature is not wholly inside executable file-backed bytes")
        offset = section.PointerToRawData + rva - section.VirtualAddress
        data = bytearray(self.data[offset : offset + length])
        mask = (1 << length) - 1
        for block in getattr(self.pe, "DIRECTORY_ENTRY_BASERELOC", ()):
            for relocation in block.entries:
                if relocation.type == pefile.RELOCATION_TYPE["IMAGE_REL_BASED_ABSOLUTE"]:
                    continue
                if relocation.type != pefile.RELOCATION_TYPE["IMAGE_REL_BASED_HIGHLOW"]:
                    raise ValueError("Unsupported relocation in x86 image")
                for address in range(
                    max(rva, relocation.rva), min(rva + length, relocation.rva + 4)
                ):
                    data[address - rva] = 0
                    mask &= ~(1 << (address - rva))
        return {"rva": rva, "bytes": data.hex(), "mask": mask}

    def describe(self):
        markers = []
        for match in re.finditer(rb"1\.[0-9][a-zA-Z0-9.]+\.J[0-9]+(?=-)", self.data):
            markers.append(
                {
                    "game_build": match[0].decode("ascii"),
                    "rva": self.pe.get_rva_from_offset(match.start()),
                }
            )
        return {
            "sha256": hashlib.sha256(self.data).hexdigest(),
            "image_base": self.pe.OPTIONAL_HEADER.ImageBase,
            "image_size": self.pe.OPTIONAL_HEADER.SizeOfImage,
            "version_markers": markers,
            "sections": [
                {
                    "name": s.Name.rstrip(b"\0").decode("ascii", errors="replace"),
                    "rva": s.VirtualAddress,
                    "size": s.Misc_VirtualSize,
                    "flags": s.Characteristics,
                }
                for s in self.pe.sections
            ],
            "imports": [
                item.dll.decode("ascii") for item in getattr(self.pe, "DIRECTORY_ENTRY_IMPORT", ())
            ],
        }
