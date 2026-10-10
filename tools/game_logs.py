"""Log locations in an owned isolated game profile."""


def probe_path(lab):
    native = lab / "profile/Documents/My Games/Binding of Isaac Repentance+/isaac-lan/probe.log"
    # Older frozen DLLs still write to the lab root. Select the current run
    # when comparing builds in a profile that contains both generations.
    present = [path for path in (native, lab / "probe.log") if path.is_file()]
    return max(present, key=lambda path: path.stat().st_mtime_ns) if present else native
