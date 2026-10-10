"""Prepare J460 progress fixtures before native menus cache character unlocks."""

from pathlib import Path
import os
import struct
import tempfile

MAGIC = b"ISAACNGSAVE09R  "
PROFILE = Path("profile/Documents/My Games/Binding of Isaac Repentance+")


def checksum(data):
    # J460 uses arithmetic shifts when generating its CRC table. Its result
    # differs from standard CRC32. The magic is excluded, the opaque version
    # word is included, and the checksum is stored at the end of the file.
    table = []
    for value in range(256):
        for _ in range(8):
            signed = value if value < 0x80000000 else value - 0x100000000
            value = ((signed >> 1) ^ (-int(value & 1) & 0xEDB88320)) & 0xFFFFFFFF
        table.append(value)
    result = 0xFEDCBA76 ^ 0xFFFFFFFF
    for value in data:
        result = (result >> 8) ^ table[(result ^ value) & 255]
    return result ^ 0xFFFFFFFF


def patch(source, *, host, endings=False, alt_path=False, hush=False, ascent=False):
    if not 2800 <= len(source) <= 4 * 1024 * 1024 or source[:16] != MAGIC:
        raise ValueError("A native J460 persistentgamedata1.dat baseline is required")
    if struct.unpack_from("<I", source, len(source) - 4)[0] != checksum(source[16:-4]):
        raise ValueError("Native progress baseline checksum differs")
    if struct.unpack_from("<3I", source, 20) != (1, 642, 642):
        raise ValueError("Unsupported native achievement section")
    counter_section = 32 + 642
    if struct.unpack_from("<3I", source, counter_section) != (2, 523 * 4, 523):
        raise ValueError("Unsupported native counter section")
    data = bytearray(source)
    achievements = memoryview(data)[32 : 32 + 642]
    if any(value > 1 for value in achievements):
        raise ValueError("Invalid native achievement flags")
    counters = counter_section + 12
    achievements[640] = int(host)
    struct.pack_into("<I", data, counters + 522 * 4, 98765 if host else 321)
    if ascent and host:
        for identifier in (4, 57, 635):
            achievements[identifier] = 1
    if endings:
        if host:
            achievements[:] = bytes([1]) * 642
        else:
            achievements[407] = 0
    if hush:
        achievements[320] = int(host)
        struct.pack_into("<I", data, counters + 158 * 4, 3 if host else 0)
    if alt_path:
        achievements[407] = int(host)
        achievements[412] = 0
    del achievements
    struct.pack_into("<I", data, len(data) - 4, checksum(data[16:-4]))
    return bytes(data)


def prepare(lab, **options):
    lab = Path(lab).resolve()
    path = lab / PROFILE / "persistentgamedata1.dat"
    if not (lab / ".isaac-lan-lab").is_file() or not path.resolve().is_relative_to(lab):
        raise ValueError("An owned isolated progress file is required")
    data = patch(path.read_bytes(), **options)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            dir=path.parent, prefix=".lan-progress-", delete=False
        ) as f:
            temporary = Path(f.name)
            f.write(data)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
