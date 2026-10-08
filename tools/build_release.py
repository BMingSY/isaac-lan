#!/usr/bin/env python3
"""Build a versioned installer ZIP and its SHA-256 file. Does not publish."""

import argparse
import hashlib
import json
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile

from build_package import build


def release(build_directory, output, tag):
    version = (Path(__file__).resolve().parents[1] / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or tag != f"v{version}":
        raise ValueError("Release tag must match VERSION")
    name = f"Isaac-LAN-{tag}-windows-x86"
    output.mkdir(parents=True, exist_ok=True)
    package = output / name
    archive = output / f"{name}.zip"
    checksum = output / f"{name}.zip.sha256"
    if package.exists() or archive.exists() or checksum.exists():
        raise FileExistsError("Release output already exists; choose a fresh directory")
    payload = build(build_directory, package)
    with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=9) as zipped:
        for path in sorted(package.rglob("*")):
            if path.is_file():
                zipped.write(path, f"{name}/{path.relative_to(package).as_posix()}")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum.write_text(f"{digest}  {archive.name}\n", encoding="ascii")
    return {"tag": tag, "archive": str(archive), "sha256": digest, "payload": payload}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    print(json.dumps(release(args.build, args.output, args.tag), indent=2))
