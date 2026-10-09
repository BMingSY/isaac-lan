"""Persistent Lua 5.3 worker for testing production modules without the game."""

import json
from pathlib import Path
import queue
import shutil
import struct
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]


def encode(value):
    if isinstance(value, bool):
        return bytes([int(value)])
    if isinstance(value, int):
        return (
            (b"\x02" + struct.pack(">i", value))
            if -(2**31) <= value < 2**31
            else (b"\x03" + struct.pack(">q", value))
        )
    if isinstance(value, float):
        return b"\x04" + struct.pack(">f", value)
    if isinstance(value, str):
        data = value.encode("utf-8")
        return b"\x05" + struct.pack(">H", len(data)) + data
    if isinstance(value, list):
        return b"\x06" + struct.pack(">H", len(value)) + b"".join(map(encode, value))
    raise TypeError(f"Unsupported test value: {type(value).__name__}")


def decode(data):
    cursor = 0

    def read(fmt):
        nonlocal cursor
        result = struct.unpack_from(fmt, data, cursor)[0]
        cursor += struct.calcsize(fmt)
        return result

    def get():
        nonlocal cursor
        tag = read(">B")
        if tag < 2:
            return bool(tag)
        if tag in (2, 3, 4):
            return read({2: ">i", 3: ">q", 4: ">f"}[tag])
        if tag == 5:
            size = read(">H")
            value = data[cursor : cursor + size].decode("utf-8")
            cursor += size
            return value
        if tag == 6:
            return [get() for _ in range(read(">H"))]
        raise ValueError(f"Unknown worker tag: {tag}")

    result = get()
    if cursor != len(data):
        raise ValueError("Trailing worker bytes")
    return result


class LuaWorker:
    def __init__(self, executable=None):
        lua = executable or shutil.which("lua5.3") or shutil.which("lua")
        if not lua:
            raise RuntimeError("Install Lua 5.3 to run offline behavior and state tests")
        self.history = []
        self.lines = queue.Queue()
        self.process = subprocess.Popen(
            [lua, str(ROOT / "tests/offline/lua_worker.lua"), str(ROOT)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=ROOT,
        )
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            assert self.call("version") == ["Lua 5.3"]
        except BaseException:
            self.close()
            raise

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def call(self, action, *args):
        if action.endswith("_reset"):
            self.history.clear()
        request = [action, *args]
        self.history.append({"request": request})
        self.process.stdin.write(encode(request).hex() + "\n")
        self.process.stdin.flush()
        try:
            line = self.lines.get(timeout=20)
        except queue.Empty as error:
            raise RuntimeError(f"Offline Lua action timed out: {action}") from error
        if line is None:
            raise RuntimeError("Offline Lua worker exited: " + self.process.stderr.read())
        ok, value = decode(bytes.fromhex(line.strip()))
        self.history[-1]["response"] = value
        if not ok:
            raise AssertionError(f"Offline action {action}: {value}")
        return value

    def save(self, path):
        Path(path).write_text(json.dumps(self.history, ensure_ascii=False, indent=2) + "\n")

    def close(self):
        if self.process.stdin:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.reader.join(timeout=5)
        self.process.stdout.close()
        self.process.stderr.close()
