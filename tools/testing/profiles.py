"""Startup-only native profile fixtures shared by acceptance suites."""

import struct
from progress_fixture import MAGIC, checksum


def profile_fixture(source, *, negative=True, tainted_cain=True):
    """Prepare startup-only qualification while preserving every unrelated byte."""
    if not 2800 <= len(source) <= 4 * 1024 * 1024 or source[:16] != MAGIC:
        raise ValueError("A native J460 progress baseline is required")
    if struct.unpack_from("<I", source, len(source) - 4)[0] != checksum(source[16:-4]):
        raise ValueError("Native progress baseline checksum differs")
    if struct.unpack_from("<3I", source, 20) != (1, 642, 642):
        raise ValueError("Unsupported native achievement section")
    if struct.unpack_from("<3I", source, 674) != (2, 523 * 4, 523):
        raise ValueError("Unsupported native counter section")
    if any(value > 1 for value in source[32:674]):
        raise ValueError("Invalid native achievement flags")
    data = bytearray(source)
    for identifier, unlocked in ((4, True), (34, True), (78, negative), (476, tainted_cain)):
        data[32 + identifier] = int(unlocked)
    struct.pack_into("<I", data, len(data) - 4, checksum(data[16:-4]))
    return bytes(data)


def magdalene_profile(source):
    """Unlock only native Magdalene in a startup-only disposable profile."""
    if not 2800 <= len(source) <= 4 * 1024 * 1024 or source[:16] != MAGIC:
        raise ValueError("A native J460 progress baseline is required")
    if struct.unpack_from("<I", source, len(source) - 4)[0] != checksum(source[16:-4]):
        raise ValueError("Native progress checksum differs")
    if struct.unpack_from("<3I", source, 20) != (1, 642, 642):
        raise ValueError("Unsupported native achievement section")
    if any(flag > 1 for flag in source[32:674]):
        raise ValueError("Invalid native achievement flags")
    data = bytearray(source)
    data[32 + 1] = 1
    struct.pack_into("<I", data, len(data) - 4, checksum(data[16:-4]))
    return bytes(data)
