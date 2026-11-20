"""Startup-only native profile fixtures shared by acceptance suites."""

import struct
from progress_fixture import AZAZEL_ACHIEVEMENT, MAGDALENE_ACHIEVEMENT, checksum, progress_layout


def profile_fixture(source, *, negative=True, tainted_cain=True):
    """Prepare startup-only qualification while preserving every unrelated byte."""
    progress_layout(source)
    data = bytearray(source)
    for identifier, unlocked in ((4, True), (34, True), (78, negative), (476, tainted_cain)):
        data[32 + identifier] = int(unlocked)
    struct.pack_into("<I", data, len(data) - 4, checksum(data[16:-4]))
    return bytes(data)


def _achievement_profile(source, identifier):
    """Unlock one qualification without changing counters or opaque sections."""
    progress_layout(source)
    data = bytearray(source)
    data[32 + identifier] = 1
    struct.pack_into("<I", data, len(data) - 4, checksum(data[16:-4]))
    return bytes(data)


def magdalene_profile(source):
    """Unlock only native Magdalene in a startup-only disposable profile."""
    return _achievement_profile(source, MAGDALENE_ACHIEVEMENT)


def azazel_profile(source):
    """Unlock only native Azazel in a startup-only disposable profile."""
    return _achievement_profile(source, AZAZEL_ACHIEVEMENT)
