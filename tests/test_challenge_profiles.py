"""Startup qualification fixtures must not grant unrelated native progress."""

from pathlib import Path
import struct
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from progress_fixture import MAGIC, checksum
from testing.challenges import completion_evidence
from testing.profiles import profile_fixture


def baseline():
    source = (
        MAGIC
        + struct.pack("<4I", 0x10203040, 1, 642, 642)
        + bytes(i % 2 for i in range(642))
        + struct.pack("<3I", 2, 523 * 4, 523)
        + struct.pack("<523I", *range(523))
        + b"opaque native sections" * 30
    )
    return source + struct.pack("<I", checksum(source[16:]))


@pytest.mark.parametrize(
    "negative,tainted_cain", [(True, True), (False, True), (True, False), (False, False)]
)
def test_only_explicit_qualification_flags_change(negative, tainted_cain):
    source = baseline()
    result = profile_fixture(source, negative=negative, tainted_cain=tainted_cain)
    flags = bytearray(source[32:674])
    flags[4] = flags[34] = 1
    flags[78], flags[476] = int(negative), int(tainted_cain)
    assert result[32:674] == flags
    assert result[:32] == source[:32]
    assert result[674:-4] == source[674:-4]
    assert len(result) == len(source)
    assert struct.unpack_from("<I", result, len(result) - 4)[0] == checksum(result[16:-4])
    assert profile_fixture(result, negative=negative, tainted_cain=tainted_cain) == result


def test_corrupt_or_unsupported_profiles_are_rejected():
    source = baseline()
    corrupt = bytearray(source)
    corrupt[33] ^= 1
    with pytest.raises(ValueError, match="checksum"):
        profile_fixture(corrupt)
    for offset, value in ((20, 3), (24, 641), (674, 7), (32, 2)):
        corrupt = bytearray(source)
        struct.pack_into("<I", corrupt, offset, value)
        struct.pack_into("<I", corrupt, len(corrupt) - 4, checksum(corrupt[16:-4]))
        with pytest.raises(ValueError):
            profile_fixture(corrupt)


@pytest.mark.parametrize("ordinal,expected", [(0, 3), (1, 3), (2, 2), (3, 1)])
def test_trophy_completion_requires_each_native_finish(ordinal, expected):
    direction = "SENT" if ordinal == 0 else "RECEIVED"
    line = f"[time] ending_event={direction} id=0 completed=1\n"
    result = completion_evidence(line * expected, ordinal=ordinal, players=4)
    assert result["expected"] == expected and result["passed"]
    for incorrect in (
        line * (expected - 1),
        line * (expected + 1),
        (line * expected).replace("completed=1", "completed=0", 1),
        (line * expected).replace(" completed=1", "", 1),
    ):
        assert not completion_evidence(incorrect, ordinal=ordinal, players=4)["passed"]


def test_hud_suite_exits_without_claiming_challenge_completion():
    assert completion_evidence("", ordinal=0, players=4, expected=0)["passed"]
    assert not completion_evidence(
        "ending_event=SENT id=6 completed=1", ordinal=0, players=4, expected=0
    )["passed"]
