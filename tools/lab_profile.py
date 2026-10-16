"""Protect owned lab data independently of any particular gameplay suite."""

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def windows(path):
    return subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()


def idle(labs):
    command = (
        "@(Get-Process -Name isaac-ng -ErrorAction SilentlyContinue | "
        "ForEach-Object { $_.Path }) | ConvertTo-Json -Compress"
    )
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    )
    paths = json.loads(result.stdout or "[]") or []
    if isinstance(paths, str):
        paths = [paths]
    if {windows(lab / "game/isaac-ng.exe").casefold() for lab in labs} & {
        path.casefold() for path in paths
    }:
        raise RuntimeError("The selected isolated lab already has a running game")


def hashes(directory):
    return {
        str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in directory.rglob("*")
        if p.is_file()
    }


@dataclass(frozen=True)
class Backup:
    source: Path
    destination: Path
    baseline: dict
    existed: bool


class ProtectedLabs:
    def __init__(self, labs, output, roles=("host", "client")):
        self.labs = tuple(labs)
        roles = tuple(roles)
        if len(roles) < len(self.labs) or len(set(self.labs)) != len(self.labs):
            raise ValueError("Distinct labs and one role per lab are required")
        if any(not (lab / ".isaac-lan-lab").is_file() for lab in self.labs):
            raise ValueError("Only marked isolated labs can be protected")
        self.entries = []
        for role, lab in zip(roles, self.labs):
            for folder in ("profile", "game/data", "game/isaac-lan"):
                source = lab / folder
                destination = output / "before" / role / folder
                baseline = hashes(source)
                existed = source.exists()
                if existed:
                    shutil.copytree(source, destination)
                    if hashes(destination) != baseline:
                        raise RuntimeError("Lab backup differs: " + str(source))
                self.entries.append(Backup(source, destination, baseline, existed))

    def report(self):
        return {
            str(entry.source): {"before": entry.baseline, "existed": entry.existed}
            for entry in self.entries
        }

    def restore(self):
        # Check all processes and backups before replacing any live data.
        idle(self.labs)
        for entry in self.entries:
            if entry.existed and (
                not entry.destination.is_dir() or hashes(entry.destination) != entry.baseline
            ):
                raise RuntimeError("Lab backup is missing or changed: " + str(entry.destination))
        errors, restored = [], {}
        for entry in self.entries:
            try:
                if entry.source.exists():
                    shutil.rmtree(entry.source)
                if entry.existed:
                    shutil.copytree(entry.destination, entry.source)
                restored[str(entry.source)] = hashes(entry.source)
                if restored[str(entry.source)] != entry.baseline:
                    raise RuntimeError("Restored lab files differ: " + str(entry.source))
            except Exception as error:
                errors.append(str(error))
        if errors:
            raise RuntimeError("; ".join(errors))
        return restored
