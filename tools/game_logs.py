"""Log discovery and complete launch evidence in an owned isolated profile."""

from pathlib import Path
import re
import shutil


def launch_directory(lab, process_id=None):
    logs = lab / "profile/Documents/My Games/Binding of Isaac Repentance+/isaac-lan/logs"
    candidates = [
        path
        for path in logs.glob("*")
        if path.is_dir()
        and (path / "startup.log").is_file()
        and (process_id is None or re.search(rf"-p{int(process_id)}(?:-\d+)?$", path.name))
    ]
    return max(candidates, key=lambda path: path.name) if candidates else None


def probe_path(lab):
    launch = launch_directory(lab)
    if launch:
        return launch / "startup.log"
    native = lab / "profile/Documents/My Games/Binding of Isaac Repentance+/isaac-lan/probe.log"
    present = [path for path in (native, lab / "probe.log") if path.is_file()]
    return max(present, key=lambda path: path.stat().st_mtime_ns) if present else native


def probe_text(lab, process_id=None):
    launch = launch_directory(lab, process_id)
    if not launch:
        if process_id is not None and launch_directory(lab) is not None:
            return ""  # Never attach another process's evidence to this run.
        path = probe_path(lab)
        return path.read_text(errors="replace") if path.is_file() else ""
    # startup.log also receives inter-run and shutdown events. Merge by the
    # timestamp, rather than concatenating it ahead of every game's log.
    lines = []
    for path in sorted(launch.rglob("*.log")):
        lines.extend(path.read_text(errors="replace").splitlines())
    return "\n".join(sorted(lines, key=lambda line: line.partition("]")[0])) + "\n"


def freeze_probe_logs(lab, destination, process_id=None):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "probe.log").write_text(probe_text(lab, process_id))
    launch = launch_directory(lab, process_id)
    if launch:
        shutil.copytree(launch, destination / "logs" / launch.name, dirs_exist_ok=True)
