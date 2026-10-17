"""Commands and supervised children for the native acceptance backend."""

from contextlib import contextmanager
from pathlib import Path
import subprocess
import sys
import signal


ROOT = Path(__file__).resolve().parents[2]
CLEANUP_TIMEOUT = 120


class BackendCleanupError(RuntimeError):
    """The owning backend may still write data or launch/close native children."""


def configure_interrupts():
    """Unwind protection even when a background shell inherited SIGINT ignored."""
    for name in ("SIGINT", "SIGTERM", "SIGHUP"):
        if hasattr(signal, name):
            signal.signal(getattr(signal, name), signal.default_int_handler)


def engine_command(labs, build, output, script, completion, *options):
    """Keep suite-specific options explicit and retain the backend's CLI contract."""
    return [
        sys.executable,
        str(ROOT / "tools/run_network_engine.py"),
        "--host",
        str(labs[0]),
        "--client",
        str(labs[1]),
        "--build",
        str(build.resolve()),
        "--output",
        str(output),
        "--script",
        str(script),
        "--completion",
        completion,
        *options,
    ]


def stop_child(process):
    if process is not None and process.poll() is None:
        # The backend owns the native PIDs. Give its SIGTERM handler time to
        # close them; killing the backend could orphan the games.
        process.terminate()
        process.wait(timeout=CLEANUP_TIMEOUT)


@contextmanager
def engine_process(command, **kwargs):
    process = subprocess.Popen(command, **kwargs)
    try:
        yield process
    finally:
        try:
            stop_child(process)
        except BaseException as error:
            raise BackendCleanupError(
                "Owned backend did not finish cleanup: " + str(error)
            ) from error


def run_engine(command, **kwargs):
    with engine_process(command, **kwargs) as process:
        return subprocess.CompletedProcess(command, process.wait())


def finalize_result(result, expected_roles):
    result["scenario_pass"] = bool(result["pass"])
    exits = result.get("process_exit", {})
    errors = []
    for role in expected_roles:
        status = exits.get(role)
        if status is None:
            errors.append(f"{role}: process exit report is missing")
        elif status.get("exit_code") != 0:
            errors.append(f"{role}: process exited with {status.get('exit_hex', 'unknown')}")
    result["clean_exit"] = not errors
    if errors:
        result.setdefault("close_errors", []).extend(errors)
    result["pass"] = result["scenario_pass"] and not result.get("close_errors")
    if result.get("close_errors") and not result.get("error"):
        result["error"] = "; ".join(result["close_errors"])
