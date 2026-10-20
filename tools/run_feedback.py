#!/usr/bin/env python3
"""Check /feedback uploads from one owned pair against a local test receiver."""

import argparse
import http.server
import io
import json
from pathlib import Path
import re
import subprocess
import threading
import zipfile

from lab_profile import ProtectedLabs, idle, validate_labs, validate_startup
from testing.engine import configure_interrupts, engine_command, engine_process
from testing.results import finish_run

ROOT = Path(__file__).resolve().parents[1]
COMPLETION = "LAN_NETWORK PASS feedback"
SUBMIT = "/isaac-lan/feedback/v1/submit"
DESCRIPTIONS = {"实机反馈 主机": "1", "实机反馈 客机": "0"}
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
RUN_LOG = re.compile(r"logs/[^/]+/\d{3}-[A-Z0-9]{8}-(?:host|client)/runtime\.log")


class Receiver(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, port):
        super().__init__(("127.0.0.1", port), Handler)
        self.lock = threading.Lock()
        self.uploads = []


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        with self.server.lock:
            index = len(self.server.uploads) + 1
            self.server.uploads.append(
                {"path": self.path, "headers": dict(self.headers), "body": body}
            )
        # Same response contract as the release receiver.
        payload = json.dumps({"id": f"000000-{index:04d}", "duplicate": False}).encode()
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        pass


def inspect(upload):
    """Return the manifest after checking headers and the zip contract."""
    headers = upload["headers"]
    assert upload["path"] == SUBMIT, upload["path"]
    assert headers.get("Content-Type") == "application/zip"
    assert UUID.fullmatch(headers.get("X-Feedback-Submission", ""))
    assert UUID.fullmatch(headers.get("X-Feedback-Install", ""))
    assert re.fullmatch(r"isaac-lan/\d+\.\d+\.\d+", headers.get("X-Feedback-Client", ""))
    with zipfile.ZipFile(io.BytesIO(upload["body"])) as archive:
        assert archive.testzip() is None
        manifest = json.loads(archive.read("feedback.json"))
        names = archive.namelist()
        assert names == ["feedback.json", *manifest["files"]], names
        assert "game/log.txt" in names and "config/config.ini" in names
        assert any(RUN_LOG.fullmatch(name) for name in names), names
        assert b"[feedback]" in archive.read("config/config.ini")
    assert manifest["schema"] == 1 and manifest["game"] == "1.9.7.17.J460"
    assert manifest["context"]["phase"] == "running"
    return manifest


def main():
    configure_interrupts()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build-win32")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=30850)
    parser.add_argument("--receiver-port", type=int, default=30851)
    parser.add_argument("--heap-check", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.port < 65535 or not 1 <= args.receiver_port < 65535:
        parser.error("Invalid port")
    output = args.output.resolve()
    labs = validate_labs([args.host, args.client], output)
    idle(labs)
    validate_startup(labs)
    output.mkdir(parents=True, exist_ok=False)
    protected = ProtectedLabs(labs, output)
    report = {"passed": False, "protected": protected.report(), "uploads": []}
    receiver = Receiver(args.receiver_port)
    threading.Thread(target=receiver.serve_forever, daemon=True).start()
    command = engine_command(
        labs,
        args.build,
        output / "engine",
        ROOT / "tests/state_feedback.lua",
        COMPLETION,
        "--frontend",
        "--menu-start",
        "--menu-port",
        str(args.port),
        "--feedback-endpoint",
        f"http://127.0.0.1:{args.receiver_port}{SUBMIT}",
        "--scenario-timeout",
        "240",
    )
    if args.heap_check:
        command.append("--heap-check")
    report["command"] = command
    try:
        with (
            (output / "runner.log").open("w") as log,
            engine_process(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT) as process,
        ):
            report["returncode"] = process.wait()
        result = json.loads((output / "engine/result.json").read_text())
        report["engine"] = result
        with receiver.lock:
            uploads = list(receiver.uploads)
        for index, upload in enumerate(uploads, 1):
            (output / f"upload-{index}.zip").write_bytes(upload["body"])
        manifests = [inspect(upload) for upload in uploads]
        report["uploads"] = [
            {"description": m["description"], "context": m["context"], "files": m["files"]}
            for m in manifests
        ]
        # One upload per peer; the guest's /c console entry must not upload.
        descriptions = sorted(m["description"] for m in manifests)
        assert descriptions == sorted(DESCRIPTIONS), f"uploads: {descriptions}"
        for manifest in manifests:
            hosting = manifest["context"]["hosting"]
            assert hosting == DESCRIPTIONS[manifest["description"]], f"hosting: {hosting}"
        report["passed"] = result["pass"]
    except AssertionError as error:
        report["failure"] = repr(error)
    finally:
        receiver.shutdown()
        receiver.server_close()
        finish_run(protected, report, output)
    print(json.dumps({"passed": report["passed"], "restored": report["restored"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
