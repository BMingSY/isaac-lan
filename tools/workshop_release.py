#!/usr/bin/env python3
"""Prepare, publish or verify the existing Isaac LAN Workshop item (Windows/WSL)."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ITEM_ID = "3817760679"
TITLE = "Isaac LAN / 局域网联机"
LANGUAGES = ("english", "schinese")
BASE_FILES = ("main.lua", "metadata.xml", "preview.png", "安装说明.txt")
DESCRIPTION_LIMIT = 8000


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_hashes(directory):
    result = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Symlinks are not allowed: {path}")
        if path.is_file():
            result[path.relative_to(directory).as_posix()] = digest(path)
    return result


def steam_notes(text):
    if not text.strip() or "\0" in text:
        raise ValueError("Release notes are empty or invalid")
    # Formatting only; preserve every word of the reviewed release notes.
    return re.sub(
        r"^(?:## (.+)|\*\*(.+)\*\*)$",
        lambda match: f"[b]{match[1] or match[2]}[/b]",
        text,
        flags=re.MULTILINE,
    )


def windows_path(path):
    path = Path(path).resolve()
    if os.name == "nt":
        return str(path)
    return subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()


def local_path(path):
    if os.name == "nt":
        return Path(path)
    return Path(subprocess.check_output(["wslpath", "-u", path], text=True).strip())


class Steam:
    def __init__(self, helper, game):
        self.helper = helper.resolve()
        self.dll = game.resolve() / "steam_api.dll"

    def call(self, command, prefix, *arguments):
        args = [str(self.helper), command, windows_path(self.dll), ITEM_ID, windows_path(prefix)]
        args.extend(windows_path(arg) if isinstance(arg, Path) else arg for arg in arguments)
        with prefix.with_suffix(".log").open("wb") as log:
            result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, timeout=210)
        if result.returncode:
            raise RuntimeError(f"Steam {command} failed; see {prefix.with_suffix('.log')}")
        response = read_json(prefix.with_suffix(".json"))
        if response.get("item_id") != ITEM_ID:
            raise ValueError("Steam returned a different Workshop item")
        return response

    def query(self, prefix, language):
        return self.call("query", prefix, language)

    def download(self, prefix):
        return local_path(self.call("download", prefix)["folder"])

    def update(self, prefix, content, notes):
        return self.call("update", prefix, content, notes)

    def update_page(self, prefix, content, notes, language, description, preview):
        return self.call(
            "update-page", prefix, content or "-", notes, language, description, preview or "-"
        )


def query_metadata(steam, directory):
    directory.mkdir(parents=True, exist_ok=False)
    result = {}
    for language in LANGUAGES:
        value = steam.query(directory / language, language)
        if (
            value.get("item_id") != ITEM_ID
            or value.get("visibility") != 0
            or value.get("banned") is not False
            or not value.get("owner")
        ):
            raise ValueError("Unexpected Workshop identity or visibility")
        result[language] = value
    if result["english"]["title"] != TITLE:
        raise ValueError("Workshop title differs; review it before publishing")
    # Steam may return an empty localized title; preserve it instead of renaming it.
    return result


def check_archive(archive, tag):
    result = subprocess.run(
        [sys.executable, str(ROOT / "tools/check_release.py"), str(archive), "--tag", tag],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def description_with_notes(tag, formatted, original):
    description = f"Isaac LAN {tag}\n\n{formatted.rstrip()}\n\n-----\n\n{original}"
    if "\0" in description or len(description.encode("utf-8")) >= DESCRIPTION_LIMIT:
        raise ValueError("Workshop description exceeds the Steam UTF-8 limit")
    return description


def preview_digest(url):
    if not url.startswith("https://"):
        raise ValueError("Workshop preview must use HTTPS")
    with urllib.request.urlopen(url, timeout=30) as response:
        return hashlib.sha256(response.read()).hexdigest()


def prepare(steam, archive, notes, output, tag, *, prepend_notes=False, preview=None):
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Expected a release tag such as v0.4.2")
    checked = check_archive(archive, tag)
    reviewed = notes.read_text(encoding="utf-8-sig")
    formatted = steam_notes(reviewed)
    if preview is not None and (preview.is_symlink() or not preview.is_file()):
        raise ValueError("Preview must be a regular local file")
    output.mkdir(parents=True, exist_ok=False)
    before = query_metadata(steam, output / "before")
    base = steam.download(output / "base-download")
    metadata = ET.parse(base / "metadata.xml")
    if metadata.getroot().findtext("id") != ITEM_ID:
        raise ValueError("Downloaded metadata belongs to another Workshop item")
    if metadata.getroot().find("version") is None:
        raise ValueError("Downloaded metadata has no version")
    content = output / "content"
    content.mkdir()
    for name in BASE_FILES:
        if (base / name).is_symlink():
            raise ValueError("Workshop base contains a symlink")
        shutil.copy2(base / name, content / name)
    original = (base / "metadata.xml").read_bytes().decode("utf-8")
    updated, count = re.subn(r"<version>[^<]*</version>", f"<version>{tag[1:]}</version>", original)
    if count != 1:
        raise ValueError("Expected one Workshop metadata version")
    (content / "metadata.xml").write_bytes(updated.encode("utf-8"))
    if preview is not None:
        shutil.copy2(preview, content / "preview.png")
    for source in (archive, archive.with_suffix(".zip.sha256")):
        shutil.copy2(source, content / source.name)
    if digest(content / archive.name) != checked["sha256"]:
        raise ValueError("Archive changed during preparation")
    (output / "reviewed-notes.md").write_bytes(reviewed.encode("utf-8"))
    (output / "steam-change-notes.txt").write_bytes(formatted.encode("utf-8"))
    manifest = {
        "format": 1,
        "item_id": ITEM_ID,
        "title": TITLE,
        "tag": tag,
        "archive": archive.name,
        "files": file_hashes(content),
        "reviewed_notes_sha256": digest(output / "reviewed-notes.md"),
        "steam_notes_sha256": digest(output / "steam-change-notes.txt"),
        "before": before,
    }
    if prepend_notes or preview is not None:
        descriptions = {}
        for language in LANGUAGES if prepend_notes else ("english",):
            text = before[language]["description"]
            if prepend_notes:
                text = description_with_notes(tag, formatted, text)
            path = output / f"description-{language}.txt"
            path.write_bytes(text.encode("utf-8"))
            descriptions[language] = {"file": path.name, "sha256": digest(path), "text": text}
        (output / "silent-change-notes.txt").write_bytes(b"")
        manifest["presentation"] = {
            "prepend_notes": prepend_notes,
            "descriptions": descriptions,
            "preview_sha256": digest(preview) if preview is not None else None,
        }
    write_json(output / "preparation.json", manifest)
    return manifest


def load_prepared(output):
    manifest = read_json(output / "preparation.json")
    if (
        manifest.get("format") != 1
        or manifest.get("item_id") != ITEM_ID
        or manifest.get("title") != TITLE
    ):
        raise ValueError("Unexpected preparation manifest")
    if file_hashes(output / "content") != manifest["files"]:
        raise ValueError("Prepared content changed")
    for name, key in (
        ("reviewed-notes.md", "reviewed_notes_sha256"),
        ("steam-change-notes.txt", "steam_notes_sha256"),
    ):
        if digest(output / name) != manifest[key]:
            raise ValueError("Prepared notes changed; prepare and review again")
    if steam_notes((output / "reviewed-notes.md").read_text(encoding="utf-8")) != (
        output / "steam-change-notes.txt"
    ).read_text(encoding="utf-8"):
        raise ValueError("Steam notes differ from reviewed wording")
    presentation = manifest.get("presentation")
    if presentation:
        if (output / "silent-change-notes.txt").read_bytes() != b"":
            raise ValueError("Silent language update notes changed")
        expected_languages = LANGUAGES if presentation["prepend_notes"] else ("english",)
        if set(presentation["descriptions"]) != set(expected_languages):
            raise ValueError("Prepared description languages changed")
        for language, value in presentation["descriptions"].items():
            path = output / f"description-{language}.txt"
            expected = manifest["before"][language]["description"]
            if presentation["prepend_notes"]:
                expected = description_with_notes(
                    manifest["tag"],
                    steam_notes((output / "reviewed-notes.md").read_text()),
                    expected,
                )
            if (
                value["file"] != path.name
                or value["text"] != expected
                or digest(path) != value["sha256"]
            ):
                raise ValueError("Prepared description changed")
            if path.read_bytes() != expected.encode("utf-8"):
                raise ValueError("Prepared description differs from reviewed notes and original")
        if (
            presentation["preview_sha256"]
            and digest(output / "content/preview.png") != presentation["preview_sha256"]
        ):
            raise ValueError("Prepared preview changed")
    return manifest


def publish(steam, output):
    manifest = load_prepared(output)
    if (output / "upload-started.json").exists():
        raise ValueError("Upload already attempted; verify before deciding whether to retry")
    before = query_metadata(steam, output / f"preflight-{time.time_ns()}")
    if before != manifest["before"]:
        raise ValueError("Remote item changed since preparation; prepare again")
    # Exclusive creation prevents two publishers from submitting this preparation.
    with (output / "upload-started.json").open("x", encoding="utf-8") as marker:
        json.dump({"item_id": ITEM_ID, "tag": manifest["tag"]}, marker)
    presentation = manifest.get("presentation")
    if presentation:
        for index, language in enumerate(presentation["descriptions"]):
            result = steam.update_page(
                output / f"upload-{language}",
                output / "content" if index == 0 else None,
                output / ("steam-change-notes.txt" if index == 0 else "silent-change-notes.txt"),
                language,
                output / presentation["descriptions"][language]["file"],
                output / "content/preview.png"
                if index == 0 and presentation["preview_sha256"]
                else None,
            )
            write_json(output / f"upload-result-{language}.json", result)
            if result.get("result") != 1 or result.get("legal_agreement_required") is not False:
                raise ValueError("Steam did not confirm the language update")
    else:
        result = steam.update(
            output / "upload", output / "content", output / "steam-change-notes.txt"
        )
    write_json(output / "upload-result.json", result)
    if result.get("result") != 1 or result.get("legal_agreement_required") is not False:
        raise ValueError("Steam did not confirm publication or requires its legal agreement")
    return verify(steam, output)


def verify(steam, output):
    manifest = load_prepared(output)
    report = output / f"verify-{time.time_ns()}"
    after = query_metadata(steam, report)
    presentation = manifest.get("presentation", {})
    for language in LANGUAGES:
        for field in ("item_id", "owner", "title", "description", "visibility", "banned"):
            expected = manifest["before"][language][field]
            if field == "description" and language in presentation.get("descriptions", {}):
                expected = presentation["descriptions"][language]["text"]
            if after[language][field] != expected:
                raise ValueError(f"Workshop {language} {field} changed")
    if presentation.get("preview_sha256"):
        if preview_digest(after["english"]["preview_url"]) != presentation["preview_sha256"]:
            raise ValueError("Workshop preview differs from prepared image")
    downloaded = steam.download(report / "download")
    if file_hashes(downloaded) != manifest["files"]:
        raise ValueError("Downloaded Workshop files differ from the prepared release")
    result = {
        "item_id": ITEM_ID,
        "tag": manifest["tag"],
        "title": TITLE,
        "downloaded_files_match": True,
        "metadata_unchanged": not bool(presentation.get("descriptions")),
        "metadata_matches_expected": True,
        "preview_verified": bool(presentation.get("preview_sha256")),
        "archive_sha256": manifest["files"][manifest["archive"]],
        "upload_receipt_present": (output / "upload-result.json").is_file(),
    }
    write_json(report / "verification.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "publish", "verify"))
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--tag")
    parser.add_argument("--prepend-notes", action="store_true")
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    if args.command == "prepare" and not all((args.archive, args.notes, args.tag)):
        parser.error("prepare requires --archive, --notes and --tag")
    steam = Steam(args.helper, args.game)
    if args.command == "prepare":
        result = prepare(
            steam,
            args.archive,
            args.notes,
            args.output,
            args.tag,
            prepend_notes=args.prepend_notes,
            preview=args.preview,
        )
    else:
        result = {"publish": publish, "verify": verify}[args.command](steam, args.output)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
