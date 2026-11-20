"""Construct an inert PE file for installer and game-compatibility checks."""

import struct


def game_image(profile):
    size = profile["minimum_image_size"] + 0x1000
    image = bytearray(size)
    image[:2] = b"MZ"
    struct.pack_into("<I", image, 60, 128)
    image[128:132] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", image, 132, 0x14C, len(profile["sections"]), 0, 0, 0, 224, 2)
    struct.pack_into("<H", image, 152, 0x10B)
    struct.pack_into("<I", image, 208, size)
    for index, section in enumerate(profile["sections"]):
        struct.pack_into(
            "<8sIIIIIIHHI",
            image,
            376 + index * 40,
            b"section",
            section["size"],
            section["start"],
            section["size"],
            section["start"],
            0,
            0,
            0,
            0,
            section["flags"],
        )
    marker = profile["game_build"].encode() + b"-"
    image[profile["version_rva"] : profile["version_rva"] + len(marker)] = marker
    for signature in profile["signatures"]:
        image[signature["rva"] : signature["rva"] + 16] = bytes.fromhex(signature["bytes"])
    return image
