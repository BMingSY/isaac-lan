"""Native pause assertions shared by focused and release acceptance."""

ITEMS_PAGE = {"j835": False, "j510": True}
COMPLETION = "LAN_NETWORK PASS native pause menu"


def peer_evidence(text, host, pulses, *, items_page=True):
    required = [COMPLETION, "SHORT_PRESSES edges=" + str(pulses)]
    for name in (
        "guest-start",
        *(("guest-select-items", "guest-items", "guest-items-back") if items_page else ()),
        "guest-options",
        "guest-music-change",
        "guest-root-resume",
        "guest-root-exit",
        "host-resume-after-leave",
        "guest-rejoin",
        "host-root-exit",
        "ordinary-resume",
        "final-save-exit",
    ):
        required.append("PAUSE_MENU step=" + name + " CHECK ")
    required.append("ORDINARY_RESUME_PRESERVED" if host else "REJOIN_PRESERVED")
    return {
        "passed": all(marker in text for marker in required) and "LAN_NETWORK FAILED" not in text,
        "missing": [marker for marker in required if marker not in text],
        "evidence": [line for line in text.splitlines() if "PAUSE_MENU " in line],
    }
