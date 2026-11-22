"""Prepare versioned progress fixtures before native menus cache character unlocks."""

from pathlib import Path
from dataclasses import dataclass
import os
import struct
import tempfile
from game_profiles import lab_profile, profile_directory, source_profile


@dataclass(frozen=True)
class ProgressLayout:
    magic: bytes
    achievements: int
    counters: int
    private_achievement: int
    private_counter: int


LAYOUTS = {
    "j835": ProgressLayout(b"ISAACNGSAVE09R  ", 638, 496, 637, 495),
    "j511": ProgressLayout(b"ISAACNGSAVE10R  ", 642, 523, 640, 522),
}
MAGIC = LAYOUTS["j511"].magic
PROFILE = Path("profile/Documents/My Games") / source_profile()["documents_directory"]
WOMB_ACHIEVEMENT = 4
TAINTED_LAZARUS_ACHIEVEMENT = 482
MAGDALENE_ACHIEVEMENT = 1
AZAZEL_ACHIEVEMENT = 79
AZAZEL_PLAYER_TYPE = 7


def checksum(data):
    # Both games use arithmetic shifts when generating their CRC table. Its result
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


def progress_layout(source, backend=None):
    if not 2800 <= len(source) <= 4 * 1024 * 1024:
        raise ValueError("A native progress baseline is required")
    layout = next((item for item in LAYOUTS.values() if source[:16] == item.magic), None)
    if layout is None or (backend is not None and layout != LAYOUTS.get(backend)):
        raise ValueError("A native progress baseline for the selected game build is required")
    if struct.unpack_from("<I", source, len(source) - 4)[0] != checksum(source[16:-4]):
        raise ValueError("Native progress baseline checksum differs")
    count = layout.achievements
    if struct.unpack_from("<3I", source, 20) != (1, count, count):
        raise ValueError("Unsupported native achievement section")
    if struct.unpack_from("<3I", source, 32 + count) != (2, layout.counters * 4, layout.counters):
        raise ValueError("Unsupported native counter section")
    if any(value > 1 for value in source[32 : 32 + count]):
        raise ValueError("Invalid native achievement flags")
    return layout


def patch(
    source,
    *,
    host,
    backend=None,
    endings=False,
    alt_path=False,
    hush=False,
    ascent=False,
    lazarus=False,
    knife=False,
    completion=False,
):
    layout = progress_layout(source, backend)
    counter_section = 32 + layout.achievements
    data = bytearray(source)
    achievements = memoryview(data)[32:counter_section]
    counters = counter_section + 12
    achievements[layout.private_achievement] = int(host)
    struct.pack_into("<I", data, counters + layout.private_counter * 4, 98765 if host else 321)
    if ascent and host:
        for identifier in (WOMB_ACHIEVEMENT, 57, 635):
            achievements[identifier] = 1
    if endings:
        if host:
            achievements[:] = bytes([1]) * layout.achievements
        else:
            achievements[407] = 0
    if hush:
        achievements[320] = int(host)
        struct.pack_into("<I", data, counters + 158 * 4, 3 if host else 0)
    if alt_path:
        achievements[407] = int(host)
        achievements[412] = 0
    if lazarus and not host:
        achievements[TAINTED_LAZARUS_ACHIEVEMENT] = 1
    if knife and not host:
        achievements[AZAZEL_ACHIEVEMENT] = 1
    if completion:
        # Isaac's twelve original widget layers; online bits deliberately differ
        # from the single-player marks to catch accidental blue/purple overlays.
        for layer, identifier in enumerate((173, 27, 41, 55, 69, 83, 97, 116, 130, 144, 423, 457)):
            value = ((layer + (0 if host else 1)) % 3) | (8 if host else 4)
            struct.pack_into("<I", data, counters + identifier * 4, value)
    del achievements
    struct.pack_into("<I", data, len(data) - 4, checksum(data[16:-4]))
    return bytes(data)


def prepare(lab, **options):
    lab = Path(lab).resolve()
    path = profile_directory(lab) / "persistentgamedata1.dat"
    if not (lab / ".isaac-lan-lab").is_file() or not path.resolve().is_relative_to(lab):
        raise ValueError("An owned isolated progress file is required")
    profile = lab_profile(lab)
    backend = profile["backend"]
    if backend not in LAYOUTS or profile.get("testing", {}).get("progress_fixture") != backend:
        raise ValueError("No audited progress fixture for this game backend")
    data = patch(path.read_bytes(), backend=backend, **options)
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
