#!/usr/bin/env python3
"""Assemble a local, reproducible installer directory. Does not install/publish."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

def build(build_directory, output):
    source = Path(__file__).resolve().parent.parent
    output.mkdir(parents=True, exist_ok=False)
    files = {}
    for name in ('winmm.dll', 'isaac_lan_probe.dll', 'isaac_lan_check.exe'):
        contents = (build_directory / name).read_bytes()
        shutil.copy2(build_directory / name, output / name)
        files[name] = hashlib.sha256(contents).hexdigest()
    payload = {'format': 1, 'game_build': '1.9.7.17.J460', 'files': files}
    (output / 'payload.json').write_text(json.dumps(payload, indent=2) + '\n')
    shutil.copy2(source / 'package/install.ps1', output)
    shutil.copy2(source / 'README.md', output)
    for mode in ('Install', 'Uninstall'):
        (output / f'{mode}.cmd').write_bytes((
            '@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Mode '
            + mode + '\r\npause\r\n').encode('ascii'))
    shutil.copytree(source / 'third_party', output / 'licenses')
    return payload

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.build, args.output), indent=2))
