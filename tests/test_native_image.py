"""Check audit candidates, PE address translation and relocation-safe evidence offline."""

import struct

import pytest

from inspect_engine import inspect
from native_image import NativeImage, Pattern


@pytest.fixture
def executable(tmp_path):
    data = bytearray(0xA00)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 60, 128)
    data[128:132] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", data, 132, 0x14C, 3, 0, 0, 0, 224, 2)
    struct.pack_into("<H", data, 152, 0x10B)
    struct.pack_into("<III", data, 180, 0x400000, 0x1000, 0x200)
    struct.pack_into("<II", data, 208, 0x4000, 0x400)
    struct.pack_into("<I", data, 244, 16)
    struct.pack_into("<II", data, 288, 0x3000, 12)
    for i, (name, flags) in enumerate(
        [(b".text", 0x60000020), (b".rdata", 0x40000040), (b".reloc", 0x42000040)]
    ):
        struct.pack_into(
            "<8sIIIIIIHHI",
            data,
            376 + i * 40,
            name,
            0x180,
            0x1000 * (i + 1),
            0x200,
            0x400 + i * 0x200,
            0,
            0,
            0,
            0,
            flags,
        )
    data[0x420:0x430] = bytes.fromhex("558baabbccdd9090909090909090909090")
    for offset in (0x440, 0x450, 0x620):
        data[offset : offset + 3] = bytes.fromhex("102030")
    marker = b"1.7.9b.J835-"
    data[0x640 : 0x640 + len(marker)] = marker
    struct.pack_into("<IIHH", data, 0x800, 0x1000, 12, 0x3022, 0)
    path = tmp_path / "game.exe"
    path.write_bytes(data)
    return path


def test_patterns_keep_overlapping_and_nibble_matches():
    assert list(Pattern.parse("aa aa").find(bytes.fromhex("aaaaaa"))) == [0, 1]
    pattern = Pattern.parse("55 a? ?1")
    assert list(pattern.find(bytes.fromhex("0055ab2155a71155b721"))) == [1, 4]
    assert list(pattern.find(bytes.fromhex("55ab"))) == []


@pytest.mark.parametrize("pattern", ["", "?", "??", "a? ?b", "55gg", "!558b", "558"])
def test_malformed_or_unanchored_patterns_are_rejected(pattern):
    with pytest.raises(ValueError):
        Pattern.parse(pattern)


def test_scan_reports_rvas_and_preserves_ambiguity(executable):
    before = executable.read_bytes()
    image = NativeImage(executable)
    assert image.scan("10 20 30") == [0x1040, 0x1050]
    assert image.scan("55 8b ?? ?? ?? ?? 90") == [0x1020]
    assert image.scan("deadbeef") == []
    assert image.describe()["version_markers"] == [{"game_build": "1.7.9b.J835", "rva": 0x2040}]
    assert executable.read_bytes() == before


def test_signature_masks_exact_relocated_bytes(executable):
    image = NativeImage(executable)
    signature = image.signature(0x1020)
    assert signature == {
        "rva": 0x1020,
        "bytes": "558b0000000090909090909090909090",
        "mask": 0xFFC3,
    }
    # A relocation beginning before the sampled range still overlaps its first byte.
    assert image.signature(0x1025)["mask"] == 0xFFFE
    for rva in (0x1178, 0x2000, 0x4000, -1):
        with pytest.raises(ValueError):
            image.signature(rva)


def test_invalid_pe_architecture_and_raw_bounds_are_rejected(executable):
    original = executable.read_bytes()
    executable.write_bytes(b"not a PE image")
    with pytest.raises(ValueError, match="Invalid PE"):
        NativeImage(executable)
    data = bytearray(original)
    struct.pack_into("<H", data, 132, 0x8664)
    executable.write_bytes(data)
    with pytest.raises(ValueError, match="Windows x86"):
        NativeImage(executable)
    data = bytearray(original)
    struct.pack_into("<I", data, 396, 0x10000)
    executable.write_bytes(data)
    with pytest.raises(ValueError, match="bounds"):
        NativeImage(executable)


def test_reference_overloads_and_virtual_names_are_retained(executable, tmp_path):
    functions = tmp_path / "reference/libzhl/functions"
    functions.mkdir(parents=True)
    (functions / "Sample.zhl").write_text("""
"558b": __thiscall void Example::Use(int value);
"102030": __thiscall void Example::Use(int value, bool enabled);
struct DifferentName {
    __vtable {
        "558b": void Update();
    }
};
""")
    report = inspect(executable, tmp_path / "reference")
    overload = report["symbols"]["Example::Use"]
    assert overload["status"] == "overloaded"
    assert [item["rvas"] for item in overload["overloads"]] == [["0x1020"], ["0x1040", "0x1050"]]
    assert report["symbols"]["DifferentName::Update"]["rvas"] == ["0x1020"]


def test_global_matches_keep_distinct_targets_and_outside_image_values(executable, tmp_path):
    data = bytearray(executable.read_bytes())
    for offset, target in [(0x460, 0x402100), (0x470, 0x402104), (0x480, 0x1234)]:
        data[offset : offset + 6] = b"\xa1" + struct.pack("<I", target) + b"\xc3"
    executable.write_bytes(data)
    functions = tmp_path / "reference/libzhl/functions"
    functions.mkdir(parents=True)
    (functions / "Globals.zhl").write_text('"a1(????????)c3": reference Object *g_Object;\n')
    report = inspect(executable, tmp_path / "reference")
    entry = report["symbols"]["g_Object"]
    assert entry["status"] == "unresolved" and "referenced_rva" not in entry
    assert entry["references"] == [
        {"instruction_rva": "0x1060", "target_rva": "0x2100", "in_image": True},
        {"instruction_rva": "0x1070", "target_rva": "0x2104", "in_image": True},
        {"instruction_rva": "0x1080", "target_rva": "-0x3fedcc", "in_image": False},
    ]


def test_missing_reference_cannot_report_an_empty_success(executable, tmp_path):
    with pytest.raises(ValueError, match="Reference checkout"):
        inspect(executable, tmp_path / "missing")
