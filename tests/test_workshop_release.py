"""Workshop publication boundaries without Steam, credentials or public writes."""

from copy import deepcopy
import hashlib
from pathlib import Path
import shutil

import pytest

import workshop_release as workshop


class FakeSteam:
    def __init__(self, base):
        self.base = base
        self.calls = []
        self.fail_upload = False
        self.metadata = {
            language: {
                "item_id": workshop.ITEM_ID,
                "owner": "42",
                "title": workshop.TITLE if language == "english" else "",
                "description": "Existing description / 保留原介绍",
                "visibility": 0,
                "banned": False,
                "updated": 1,
            }
            for language in workshop.LANGUAGES
        }

    def query(self, prefix, language):
        self.calls.append("query")
        return deepcopy(self.metadata[language])

    def download(self, prefix):
        self.calls.append("download")
        return self.base

    def update(self, prefix, content, notes):
        self.calls.append("update")
        if self.fail_upload:
            raise TimeoutError("unknown submission outcome")
        self.uploaded_notes = notes.read_text(encoding="utf-8")
        shutil.rmtree(self.base)
        shutil.copytree(content, self.base)
        for value in self.metadata.values():
            value["updated"] += 1
        return {"item_id": workshop.ITEM_ID, "result": 1, "legal_agreement_required": False}


@pytest.fixture
def release(tmp_path, monkeypatch):
    base = tmp_path / "downloaded"
    base.mkdir()
    (base / "metadata.xml").write_text(
        f"<metadata><id>{workshop.ITEM_ID}</id><name>Isaac LAN</name>"
        "<description>Existing description / 保留原介绍</description>"
        "<version>0.4.1</version></metadata>",
        encoding="utf-8",
    )
    for name in ("main.lua", "preview.png", "安装说明.txt", "old-version.zip"):
        (base / name).write_bytes(b"existing content")
    archive = tmp_path / "Isaac-LAN-v0.4.2-windows-x86.zip"
    archive.write_bytes(b"release validated by the package checker")
    archive.with_suffix(".zip.sha256").write_text(
        f"{workshop.digest(archive)}  {archive.name}\n", encoding="ascii"
    )
    notes = tmp_path / "notes.md"
    notes.write_text("**BUG修复**\n\n- 修复崩溃。\n", encoding="utf-8")
    # PE and archive contracts have their own packaging tests; exercise the
    # publisher's trust boundary using the checker's already validated digest.
    expected = hashlib.sha256(archive.read_bytes()).hexdigest()
    monkeypatch.setattr(workshop, "check_archive", lambda *_: {"sha256": expected})
    return FakeSteam(base), archive, notes, tmp_path / "prepared"


def prepare(release):
    steam, archive, notes, output = release
    return workshop.prepare(steam, archive, notes, output, "v0.4.2")


def test_prepare_uses_fresh_content_and_never_publishes(release):
    steam, archive, notes, output = release
    before = workshop.file_hashes(steam.base)
    manifest = prepare(release)
    assert "update" not in steam.calls
    assert workshop.file_hashes(steam.base) == before
    assert set(manifest["files"]) == set(workshop.BASE_FILES) | {
        archive.name,
        archive.with_suffix(".zip.sha256").name,
    }
    assert manifest["files"][archive.name] == workshop.digest(archive)
    assert "<version>0.4.2</version>" in (output / "content/metadata.xml").read_text()
    assert manifest["before"]["schinese"]["title"] == ""
    assert (output / "reviewed-notes.md").read_bytes() == notes.read_bytes()
    assert (output / "steam-change-notes.txt").read_text() == "[b]BUG修复[/b]\n\n- 修复崩溃。\n"
    with pytest.raises(FileExistsError):
        prepare(release)


def test_package_failure_prevents_steam_access(release, monkeypatch):
    def reject(*args):
        raise ValueError("archive checksum differs")

    monkeypatch.setattr(workshop, "check_archive", reject)
    with pytest.raises(ValueError, match="checksum"):
        prepare(release)
    assert not release[0].calls


def test_metadata_changes_only_version_and_preserves_line_endings(release):
    steam, _, _, output = release
    path = steam.base / "metadata.xml"
    original = path.read_bytes().replace(b"><", b">\r\n<")
    path.write_bytes(original)
    prepare(release)
    assert (output / "content/metadata.xml").read_bytes() == original.replace(b"0.4.1", b"0.4.2")


@pytest.mark.parametrize(
    "field,value",
    [("item_id", "other"), ("title", "Other mod"), ("visibility", 2), ("banned", True)],
)
def test_wrong_item_or_visibility_cannot_be_prepared(release, field, value):
    release[0].metadata["english"][field] = value
    with pytest.raises(ValueError):
        prepare(release)
    assert "update" not in release[0].calls


@pytest.mark.parametrize(
    "path", ["reviewed-notes.md", "steam-change-notes.txt", "content/main.lua", "content/extra.txt"]
)
def test_changed_preparation_is_rejected_before_upload(release, path):
    prepare(release)
    steam, _, _, output = release
    (output / path).write_text("changed", encoding="utf-8")
    steam.calls.clear()
    with pytest.raises(ValueError, match="changed"):
        workshop.publish(steam, output)
    assert steam.calls == []
    assert not (output / "upload-started.json").exists()


def test_symlink_is_not_uploaded(release):
    prepare(release)
    steam, _, notes, output = release
    (output / "content/unapproved.txt").symlink_to(notes)
    with pytest.raises(ValueError, match="Symlinks"):
        workshop.publish(steam, output)
    assert "update" not in steam.calls


def test_changed_remote_item_prevents_upload(release):
    prepare(release)
    steam, _, _, output = release
    steam.metadata["english"]["updated"] += 1
    with pytest.raises(ValueError, match="Remote item changed"):
        workshop.publish(steam, output)
    assert "update" not in steam.calls
    assert not (output / "upload-started.json").exists()


def test_publish_downloads_and_verifies_without_changing_metadata(release):
    manifest = prepare(release)
    steam, _, _, output = release
    result = workshop.publish(steam, output)
    assert result["downloaded_files_match"] and result["metadata_unchanged"]
    assert result["upload_receipt_present"]
    assert steam.calls.count("update") == 1
    assert workshop.file_hashes(steam.base) == manifest["files"]
    assert steam.uploaded_notes == (output / "steam-change-notes.txt").read_text()
    with pytest.raises(ValueError, match="already attempted"):
        workshop.publish(steam, output)
    assert steam.calls.count("update") == 1


def test_unknown_upload_outcome_is_never_automatically_retried(release):
    prepare(release)
    steam, _, _, output = release
    steam.fail_upload = True
    with pytest.raises(TimeoutError):
        workshop.publish(steam, output)
    assert (output / "upload-started.json").exists()
    with pytest.raises(ValueError, match="already attempted"):
        workshop.publish(steam, output)
    assert steam.calls.count("update") == 1


@pytest.mark.parametrize(
    "problem", ["old-archive", "missing-file", "different-file", "description"]
)
def test_verification_does_not_hide_partial_or_changed_publication(release, problem):
    prepare(release)
    steam, _, _, output = release
    workshop.publish(steam, output)
    if problem == "old-archive":
        (steam.base / "old-version.zip").write_bytes(b"old")
    elif problem == "missing-file":
        (steam.base / "main.lua").unlink()
    elif problem == "different-file":
        (steam.base / "main.lua").write_bytes(b"wrong")
    else:
        steam.metadata["schinese"]["description"] = "unexpected edit"
    with pytest.raises(ValueError):
        workshop.verify(steam, output)
    assert steam.calls.count("update") == 1
    assert len(list(output.glob("verify-*/verification.json"))) == 1


def test_verify_existing_release_does_not_upload(release):
    prepare(release)
    steam, _, _, output = release
    shutil.rmtree(steam.base)
    shutil.copytree(output / "content", steam.base)
    result = workshop.verify(steam, output)
    assert result["downloaded_files_match"]
    assert not result["upload_receipt_present"]
    assert "update" not in steam.calls
