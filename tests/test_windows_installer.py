"""Exercise Windows PowerShell in disposable folders, without starting Isaac.

Runs with the standard library on Windows or WSL; other platforms skip it.
The checker executable is a test double: native PE validation has its own tests.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which("powershell.exe")
OWNED = ("winmm.dll", "isaac_lan_probe.dll")


def windows_path(path):
    if os.name == "nt":
        return str(path.resolve())
    return subprocess.check_output(["wslpath", "-w", str(path.resolve())], text=True).strip()


def powershell(script, *args):
    return subprocess.run(
        [
            POWERSHELL,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            windows_path(script),
            *args,
        ],
        capture_output=True,
        input="\n",
        text=True,
        errors="replace",
        timeout=30,
    )


@unittest.skipUnless(
    POWERSHELL and (os.name == "nt" or shutil.which("wslpath")), "Windows PowerShell required"
)
class WindowsInstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shared = tempfile.TemporaryDirectory(prefix="isaac-lan-checker-")
        cls.addClassCleanup(cls.shared.cleanup)
        root = Path(cls.shared.name)
        script = root / "compile.ps1"
        cls.checker = root / "checker.exe"
        script.write_text(
            """param([string]$Output)
$ErrorActionPreference = 'Stop'
Add-Type -OutputAssembly $Output -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
public class Checker {
    public static int Main(string[] args) {
        string content = File.ReadAllText(args[0]);
        Console.WriteLine(content);
        return content == "compatible" ? 0 : content == "unsupported" ? 1 : 7;
    }
}
'@
""",
            encoding="utf-8",
        )
        result = powershell(script, windows_path(cls.checker))
        if result.returncode or not cls.checker.is_file():
            raise RuntimeError(result.stdout + result.stderr)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="isaac-lan-installer-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.package = self.root / "package [test]"
        self.game = self.root / "game [test]"
        self.package.mkdir()
        self.game.mkdir()
        (self.game / "isaac-ng.exe").write_text("compatible")
        (self.game / "save.dat").write_bytes(b"preserve saves")
        shutil.copy2(ROOT / "package/install.ps1", self.package)
        shutil.copy2(self.checker, self.package / "isaac_lan_check.exe")
        for name in OWNED:
            (self.package / name).write_bytes(name.encode())
        self.write_payload()

    def write_payload(self):
        payload = {
            "format": 1,
            "game_build": "1.9.7.17.J460",
            "files": {
                name: hashlib.sha256((self.package / name).read_bytes()).hexdigest()
                for name in (*OWNED, "isaac_lan_check.exe")
            },
        }
        (self.package / "payload.json").write_text(json.dumps(payload))

    def installed_files(self):
        paths = [self.game / name for name in OWNED] + [
            self.game / "isaac-lan/installation.json",
            self.game / ".isaac-lan-install",
        ]
        return {path.name: path.read_bytes() if path.exists() else None for path in paths}

    def run_installer(self, mode="Install", code=None, inject="", game=None):
        wrapper = self.root / "run.ps1"
        wrapper.write_text(
            "param([string]$Installer, [string]$GameDirectory, [string]$Mode)\n"
            "$ErrorActionPreference = 'Stop'\n$global:LASTEXITCODE = 0\n"
            + inject
            + "\n& $Installer -Mode $Mode -GameDirectory $GameDirectory\nexit $LASTEXITCODE\n",
            encoding="utf-8",
        )
        result = powershell(
            wrapper,
            windows_path(self.package / "install.ps1"),
            windows_path(game or self.game),
            mode,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 1 if code else 0, output)
        if code:
            codes = (code,) if isinstance(code, str) else code
            self.assertTrue(any(f"Isaac LAN [{value}]" in output for value in codes), output)
            self.assertIn("Next step:", output)
            self.assertNotIn("CategoryInfo", output)
        self.assertEqual((self.game / "save.dat").read_bytes(), b"preserve saves")
        return output

    def test_install_repair_upgrade_status_uninstall(self):
        self.run_installer()
        self.run_installer()
        (self.game / "winmm.dll").unlink()
        (self.package / "isaac_lan_probe.dll").write_bytes(b"new version")
        self.write_payload()
        self.run_installer()
        for name in OWNED:
            self.assertEqual((self.game / name).read_bytes(), (self.package / name).read_bytes())
        status = json.loads(self.run_installer("Status"))
        self.assertTrue(status["installed"])
        self.assertTrue(status["gameCompatible"])
        (self.game / "isaac-lan/session.keep").write_bytes(b"session")
        (self.game / "winmm.dll").unlink()
        # Removing the payload must not prevent uninstalling an owned installation.
        (self.package / "payload.json").unlink()
        self.run_installer("Uninstall")
        self.run_installer("Uninstall")
        self.assertTrue(all(value is None for value in self.installed_files().values()))
        self.assertEqual((self.game / "isaac-lan/session.keep").read_bytes(), b"session")
        self.assertFalse(list(self.game.glob(".isaac-lan-transaction-*")))

    def test_path_package_and_checker_errors(self):
        self.run_installer(code="GAME_PATH", game=self.game / "missing")
        original = (self.package / "payload.json").read_bytes()
        for content in (
            "{",
            "null",
            "[]",
            "[" + original.decode() + "]",
            '{"format":1}',
            '{"format":1,"files":[]}',
        ):
            with self.subTest(content=content):
                (self.package / "payload.json").write_text(content)
                self.run_installer(code="PACKAGE_INVALID")
        (self.package / "payload.json").write_bytes(original)
        for name in ("payload.json", *OWNED, "isaac_lan_check.exe"):
            with self.subTest(missing=name):
                path = self.package / name
                data = path.read_bytes()
                path.unlink()
                try:
                    self.assertIn(name, self.run_installer(code="PACKAGE_INVALID"))
                finally:
                    path.write_bytes(data)
        (self.game / "isaac-ng.exe").write_text("unsupported")
        self.run_installer(code="GAME_INCOMPATIBLE")
        self.assertFalse(json.loads(self.run_installer("Status"))["gameCompatible"])
        (self.game / "isaac-ng.exe").write_text("checker crashed")
        self.run_installer(code="CHECKER_FAILED")
        self.assertTrue(all(value is None for value in self.installed_files().values()))

    def test_invalid_records_and_conflicting_files_are_preserved(self):
        (self.game / "winmm.dll").write_bytes(b"foreign proxy")
        self.run_installer(code="FILE_CONFLICT")
        self.assertEqual((self.game / "winmm.dll").read_bytes(), b"foreign proxy")
        (self.game / "winmm.dll").unlink()
        (self.game / "isaac-lan").write_bytes(b"not a directory")
        self.run_installer(code="INSTALLATION_INVALID")
        (self.game / "isaac-lan").unlink()
        self.run_installer()
        record = self.game / "isaac-lan/installation.json"
        original = record.read_bytes()
        for content in ("{", "null", "[]", '{"format":1}', '{"format":1,"files":[]}'):
            with self.subTest(content=content):
                record.write_text(content)
                before = self.installed_files()
                self.run_installer(code="INSTALLATION_INVALID")
                self.assertEqual(self.installed_files(), before)
        record.write_bytes(original)
        (self.game / "winmm.dll").write_bytes(b"changed file")
        before = self.installed_files()
        self.run_installer("Uninstall", code="FILE_CONFLICT")
        self.assertEqual(self.installed_files(), before)

    def test_running_game_and_locked_file(self):
        self.run_installer(
            code="GAME_RUNNING",
            inject="""
function Get-Process { [pscustomobject]@{Path = (Join-Path $GameDirectory 'isaac-ng.exe')} }
""",
        )
        self.run_installer()
        before = self.installed_files()
        self.run_installer(
            code=("FILE_IN_USE", "PERMISSION_DENIED"),
            inject="""
$lock = [IO.File]::Open((Join-Path $GameDirectory 'winmm.dll'), 'Open', 'Read', 'Read')
""",
        )
        # A failed replacement of an unchanged file does not require a restore.
        self.assertEqual(self.installed_files(), before)
        self.assertFalse(list(self.game.glob(".isaac-lan-transaction-*")))

    def test_failed_uninstall_restores_files(self):
        self.run_installer()
        before = self.installed_files()
        self.run_installer(
            "Uninstall",
            code="PERMISSION_DENIED",
            inject=r"""
function Remove-Item {
    param($LiteralPath, [switch]$Recurse, [switch]$Force)
    if ((Split-Path -Leaf $LiteralPath) -eq 'installation.json') {
        throw [UnauthorizedAccessException]::new('injected delete failure')
    }
    Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
}
""",
        )
        self.assertEqual(self.installed_files(), before)
        self.assertFalse(list(self.game.glob(".isaac-lan-transaction-*")))

    def test_io_errors_roll_back_all_files(self):
        self.run_installer()
        before = self.installed_files()
        (self.package / "winmm.dll").write_bytes(b"new version")
        self.write_payload()
        for native_code, code in (
            (5, "PERMISSION_DENIED"),
            (32, "FILE_IN_USE"),
            (112, "DISK_FULL"),
        ):
            with self.subTest(code=code):
                self.run_installer(
                    code=code,
                    inject=r"""
function Move-Item {
    param($LiteralPath, $Destination, [switch]$Force)
    if ((Split-Path -Leaf $Destination) -eq 'installation.json') {
        throw [ComponentModel.Win32Exception]::new(NATIVE_CODE, 'injected write failure')
    }
    Microsoft.PowerShell.Management\Move-Item @PSBoundParameters
}
""".replace("NATIVE_CODE", str(native_code)),
                )
                self.assertEqual(self.installed_files(), before)
                self.assertFalse(list(self.game.glob(".isaac-lan-transaction-*")))

    def test_fresh_install_failure_removes_new_files(self):
        self.run_installer(
            code="IO_ERROR",
            inject=r"""
function Move-Item {
    param($LiteralPath, $Destination, [switch]$Force)
    if ((Split-Path -Leaf $Destination) -eq 'installation.json') { throw 'injected write failure' }
    Microsoft.PowerShell.Management\Move-Item @PSBoundParameters
}
""",
        )
        self.assertTrue(all(value is None for value in self.installed_files().values()))
        self.assertFalse(list(self.game.glob(".isaac-lan-transaction-*")))

    def test_failed_rollback_preserves_backups_and_continues_restoring(self):
        self.run_installer()
        before = self.installed_files()
        for name in OWNED:
            (self.package / name).write_bytes(b"new version")
        self.write_payload()
        output = self.run_installer(
            code="ROLLBACK_FAILED",
            inject=r"""
function Move-Item {
    param($LiteralPath, $Destination, [switch]$Force)
    if ((Split-Path -Leaf $Destination) -eq 'installation.json') { throw 'injected write failure' }
    Microsoft.PowerShell.Management\Move-Item @PSBoundParameters
}
function Copy-Item {
    param($LiteralPath, $Destination, [switch]$Force)
    if ((Split-Path -Leaf $LiteralPath) -eq 'old-isaac_lan_probe.dll') { throw 'injected restore failure' }
    Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
}
""",
        )
        self.assertIn("injected write failure", output)
        self.assertIn("injected restore failure", output)
        self.assertIn("Do not start the game", output)
        self.assertEqual((self.game / "winmm.dll").read_bytes(), before["winmm.dll"])
        self.assertEqual((self.game / "isaac_lan_probe.dll").read_bytes(), b"new version")
        (recovery,) = self.game.glob(".isaac-lan-transaction-*")
        self.assertIn(windows_path(recovery), output)
        record = json.loads((recovery / "recovery.json").read_text())
        for entry in record["files"]:
            name = entry["path"].replace("\\", "/").rsplit("/", 1)[-1]
            self.assertEqual((recovery / entry["backup"]).read_bytes(), before[name])

    def test_cleanup_failure_preserves_success_result(self):
        output = self.run_installer(
            inject=r"""
function Remove-Item {
    param($LiteralPath, [switch]$Recurse, [switch]$Force)
    throw [UnauthorizedAccessException]::new('injected cleanup failure')
}
"""
        )
        self.assertIn("Installed.", output)
        self.assertIn("Could not remove temporary folder", output)
        for name in OWNED:
            self.assertEqual((self.game / name).read_bytes(), (self.package / name).read_bytes())

    def test_packaged_launchers_preserve_exit_code_after_pause(self):
        launchers = self.root / "launchers with spaces"
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools/build_package.py"),
                "--build",
                str(self.package),
                "--output",
                str(launchers),
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        wrapper = self.root / "run-launcher.ps1"
        wrapper.write_text("param([string]$Launcher)\n& $Launcher\nexit $LASTEXITCODE\n")
        for code in (0, 7):
            (launchers / "install.ps1").write_text(f"exit {code}\n")
            for mode in ("Install", "Uninstall"):
                with self.subTest(mode=mode, exit_code=code):
                    result = powershell(wrapper, windows_path(launchers / f"{mode}.cmd"))
                    self.assertEqual(result.returncode, code, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
