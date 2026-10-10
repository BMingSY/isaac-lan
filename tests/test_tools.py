"""Regression tests for packaging and the game-independent test harness."""

import hashlib
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import time
import unittest
from zipfile import ZIP_DEFLATED, ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from build_gameplay_suite import CASES, CHECKPOINTS, build as build_suite
from build_special_suite import build as build_special_suite
from build_package import build
from build_release import release
from check_release import FILES, check
from delayed_relay import DelayedRelay
from game_logs import probe_path
from run_network_engine import finalize_result

ROOT = Path(__file__).resolve().parents[1]
BINARIES = ("winmm.dll", "isaac_lan_probe.dll", "isaac_lan_check.exe")


def test_greed_suite_keeps_both_modes_in_one_process_pair(tmp_path):
    script = tmp_path / "greed.lua"
    build_special_suite(script, ["greed", "greedier"])
    source = script.read_text()
    assert '_IsaacLanTest.route = "greed"' in source
    assert '_IsaacLanTest.route = "greedier"' in source
    assert source.count("PASS native Greed gameplay") == 2
    assert source.count("local originalFrame, originalGate") == 1
    assert source.count("return finished end end") == 2


class EngineExitTests(unittest.TestCase):
    def test_completed_scenario_with_heap_crash_fails_acceptance(self):
        result = {
            "pass": True,
            "process_exit": {
                "host": {"exit_code": -1073740940, "exit_hex": "C0000374"},
                "client": {"exit_code": 0, "exit_hex": "00000000"},
            },
        }
        finalize_result(result, ("host", "client"))
        self.assertTrue(result["scenario_pass"])
        self.assertFalse(result["clean_exit"])
        self.assertFalse(result["pass"])
        self.assertIn("host: process exited with C0000374", result["close_errors"])

    def test_normal_exit_and_missing_exit_evidence(self):
        for status in ({"exit_code": 0, "exit_hex": "00000000"}, None):
            with self.subTest(status=status):
                result = {"pass": True, "process_exit": {"host": status} if status else {}}
                finalize_result(result, ("host",))
                self.assertEqual(result["pass"], status is not None)
                self.assertEqual(result["clean_exit"], status is not None)

    def test_cleanup_errors_and_earlier_failures_remain_failures(self):
        for result in (
            {"pass": False, "error": "scenario failed"},
            {"pass": True, "close_errors": ["owned cleanup failed"]},
        ):
            with self.subTest(result=result):
                finalize_result(result, ())
                self.assertFalse(result["pass"])
                self.assertTrue(result["clean_exit"])


class GameLogTests(unittest.TestCase):
    def test_profile_and_frozen_build_log_locations(self):
        with tempfile.TemporaryDirectory() as directory:
            lab = Path(directory)
            current = (
                lab / "profile/Documents/My Games/Binding of Isaac Repentance+/isaac-lan/probe.log"
            )
            self.assertEqual(probe_path(lab), current)
            current.parent.mkdir(parents=True)
            current.write_text("new")
            self.assertEqual(probe_path(lab), current)
            old = lab / "probe.log"
            old.write_text("baseline")
            os.utime(old, ns=(200, 200))
            os.utime(current, ns=(100, 100))
            self.assertEqual(probe_path(lab), old)
            os.utime(current, ns=(300, 300))
            self.assertEqual(probe_path(lab), current)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.build = self.root / "build"
        self.build.mkdir()
        for name in BINARIES:
            (self.build / name).write_bytes(b"fixture:" + name.encode())
        self.tag = "v" + (ROOT / "VERSION").read_text().strip()

    def archive(self):
        result = release(self.build, self.root / "dist", self.tag)
        return Path(result["archive"])

    def rewrite_archive(self, archive, transform):
        with ZipFile(archive) as zipped:
            contents = {name: zipped.read(name) for name in zipped.namelist()}
        transform(contents)
        with ZipFile(archive, "w", compression=ZIP_DEFLATED) as zipped:
            for name, data in contents.items():
                zipped.writestr(name, data)
        self.checksum(archive)

    def checksum(self, archive):
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix(".zip.sha256").write_text(
            f"{digest}  {archive.name}\n", encoding="ascii"
        )

    def test_package_manifest_and_contents(self):
        output = self.root / "package"
        payload = build(self.build, output)
        self.assertEqual(payload["format"], 1)
        self.assertEqual(payload["game_build"], "1.9.7.17.J460")
        self.assertEqual(payload["extension_version"], self.tag[1:])
        self.assertEqual(json.loads((output / "payload.json").read_text()), payload)
        self.assertEqual(
            {p.relative_to(output).as_posix() for p in output.rglob("*") if p.is_file()}, FILES
        )
        for name in BINARIES:
            original = (self.build / name).read_bytes()
            self.assertEqual((output / name).read_bytes(), original)
            self.assertEqual(payload["files"][name], hashlib.sha256(original).hexdigest())
        self.assertEqual((output / "README.md").read_bytes(), (ROOT / "README.md").read_bytes())
        self.assertEqual(
            (output / "install.ps1").read_bytes(), (ROOT / "package/install.ps1").read_bytes()
        )
        for mode in ("Install", "Uninstall"):
            data = (output / f"{mode}.cmd").read_bytes()
            self.assertIn(b'"%~dp0install.ps1"', data)
            self.assertIn(f"-Mode {mode}\r\n".encode(), data)
            self.assertNotIn(b"\n", data.replace(b"\r\n", b""))

    def test_package_preserves_existing_output(self):
        output = self.root / "existing"
        output.mkdir()
        sentinel = output / "keep"
        sentinel.write_bytes(b"untouched")
        with self.assertRaises(FileExistsError):
            build(self.build, output)
        self.assertEqual(sentinel.read_bytes(), b"untouched")

    def test_package_requires_all_binaries(self):
        (self.build / BINARIES[-1]).unlink()
        with self.assertRaises(FileNotFoundError):
            build(self.build, self.root / "package")

    def test_release_archive_and_checksum(self):
        archive = self.archive()
        self.assertEqual(archive.name, f"Isaac-LAN-{self.tag}-windows-x86.zip")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.assertEqual(
            archive.with_suffix(".zip.sha256").read_text(), f"{digest}  {archive.name}\n"
        )
        with ZipFile(archive) as zipped:
            self.assertIsNone(zipped.testzip())
            self.assertEqual(zipped.namelist(), sorted(zipped.namelist()))
            self.assertEqual(set(zipped.namelist()), {archive.stem + "/" + name for name in FILES})

    def test_release_tag_must_match_version(self):
        for tag in ("latest", "v999.0.0", self.tag + "-test", self.tag[1:]):
            with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, "match VERSION"):
                release(self.build, self.root / "dist", tag)
        self.assertFalse((self.root / "dist").exists())

    def test_release_preserves_existing_outputs(self):
        for suffix in ("", ".zip", ".zip.sha256"):
            with self.subTest(suffix=suffix):
                output = self.root / ("dist" + str(len(suffix)))
                output.mkdir()
                existing = output / (f"Isaac-LAN-{self.tag}-windows-x86" + suffix)
                existing.write_bytes(b"untouched")
                with self.assertRaises(FileExistsError):
                    release(self.build, output, self.tag)
                self.assertEqual(existing.read_bytes(), b"untouched")

    def test_check_rejects_invalid_tag_and_filename(self):
        archive = self.archive()
        with self.assertRaisesRegex(ValueError, "version tag"):
            check(archive, "latest")
        with self.assertRaisesRegex(ValueError, "archive name"):
            check(archive, "v999.0.0")

    def test_check_rejects_changed_archive(self):
        archive = self.archive()
        archive.write_bytes(archive.read_bytes() + b"tampered")
        with self.assertRaisesRegex(ValueError, "checksum"):
            check(archive, self.tag)

    def test_check_rejects_missing_and_extra_files(self):
        archive = self.archive()
        self.rewrite_archive(archive, lambda files: files.pop(archive.stem + "/README.md"))
        with self.assertRaisesRegex(ValueError, "missing or unexpected"):
            check(archive, self.tag)
        self.rewrite_archive(archive, lambda files: files.update({"unexpected.txt": b"extra"}))
        with self.assertRaisesRegex(ValueError, "missing or unexpected"):
            check(archive, self.tag)

    def test_check_rejects_duplicate_members(self):
        archive = self.archive()
        import warnings

        with warnings.catch_warnings(), ZipFile(archive, "a") as zipped:
            warnings.simplefilter("ignore", UserWarning)
            name = archive.stem + "/README.md"
            zipped.writestr(name, zipped.read(name))
        self.checksum(archive)
        with self.assertRaisesRegex(ValueError, "missing or unexpected"):
            check(archive, self.tag)

    def test_check_rejects_manifest_changes(self):
        archive = self.archive()
        name = archive.stem + "/payload.json"
        with ZipFile(archive) as zipped:
            original = json.loads(zipped.read(name))
        for field, wrong in (
            ("format", 2),
            ("game_build", "unsupported"),
            ("extension_version", "999.0.0"),
            ("files", {}),
        ):
            with self.subTest(field=field):
                payload = dict(original)
                payload[field] = wrong
                self.rewrite_archive(
                    archive, lambda files: files.update({name: json.dumps(payload).encode()})
                )
                with self.assertRaisesRegex(ValueError, "manifest"):
                    check(archive, self.tag)

    def test_check_rejects_binary_tampering(self):
        archive = self.archive()
        name = archive.stem + "/isaac_lan_check.exe"
        self.rewrite_archive(archive, lambda files: files.update({name: b"tampered"}))
        with self.assertRaisesRegex(ValueError, "file hash"):
            check(archive, self.tag)


class GameplaySuiteTests(unittest.TestCase):
    def test_suite_preserves_fixtures_and_schedule(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "suite.lua"
            phases = build_suite(output)
            metadata = json.loads(output.with_suffix(".json").read_text())
            lua = output.read_text()
        self.assertNotIn("-- BUNDLED_FIXTURES", lua)
        self.assertEqual(metadata["phases"], phases)
        self.assertEqual(metadata["game_starts"], 1)
        self.assertEqual(metadata["clients"], 2)
        tick = 60
        for phase, (name, script, duration) in zip(phases, CASES, strict=True):
            source = (ROOT / "tests" / script).read_text()
            self.assertIn(source, lua)
            self.assertEqual(phase["name"], name)
            self.assertEqual(phase["start"], tick)
            self.assertEqual(phase["sha256"], hashlib.sha256(source.encode()).hexdigest())
            self.assertEqual(phase["checkpoints"], CHECKPOINTS[name])
            self.assertTrue(all(0 <= offset < duration for offset in phase["checkpoints"].values()))
            tick += duration + 90
        self.assertEqual(metadata["end_tick"], tick)


class RelayTests(unittest.TestCase):
    def test_guest_arrives_before_recreated_host_listener(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.settimeout(5)
            relay = DelayedRelay(0, listener.getsockname()[1], 1)
            try:
                with socket.create_connection(relay.listener.getsockname(), timeout=5) as client:
                    client.sendall(b"next lobby")
                    time.sleep(0.1)
                    self.assertIsNone(relay.error)
                    listener.listen()
                    host, _ = listener.accept()
                    with host:
                        host.settimeout(5)
                        self.assertEqual(host.recv(64), b"next lobby")
                        host.sendall(b"ready")
                        self.assertEqual(client.recv(64), b"ready")
            finally:
                relay.close()
            self.assertIsNone(relay.error)
            self.assertFalse(relay.thread.is_alive())

    def test_bidirectional_bytes_and_clean_half_close(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            listener.settimeout(5)
            relay = DelayedRelay(0, listener.getsockname()[1], 10)
            try:
                with socket.create_connection(relay.listener.getsockname(), timeout=5) as client:
                    host, _ = listener.accept()
                    with host:
                        host.settimeout(5)
                        payload = bytes(range(256)) * 1024
                        client.sendall(payload)
                        client.shutdown(socket.SHUT_WR)
                        received = bytearray()
                        while chunk := host.recv(65536):
                            received.extend(chunk)
                        self.assertEqual(received, payload)
                        host.sendall(b"finish")
                        host.shutdown(socket.SHUT_WR)
                        response = bytearray()
                        while chunk := client.recv(65536):
                            response.extend(chunk)
                        self.assertEqual(response, b"finish")
            finally:
                relay.close()
            self.assertIsNone(relay.error)
            self.assertFalse(relay.thread.is_alive())


if __name__ == "__main__":
    unittest.main()
