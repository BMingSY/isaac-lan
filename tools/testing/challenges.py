"""Shared native challenge assertions."""

import re


def completion_evidence(probe, *, ordinal, players, expected=None):
    """A trophy must broadcast FinishChallenge, rather than a normal ending."""
    lines = [line for line in probe.splitlines() if "ending_event=" in line]
    events = []
    for line in lines:
        match = re.search(r"ending_event=(SENT|RECEIVED) id=(\d+) completed=([01])\b", line)
        if match:
            events.append(
                {
                    "direction": match[1],
                    "id": int(match[2]),
                    "completed": match[3] == "1",
                }
            )
    if expected is None:
        expected = players - max(2, ordinal + 1) + 1
    direction = "SENT" if ordinal == 0 else "RECEIVED"
    return {
        "events": events,
        "expected": expected,
        "passed": len(events) == len(lines) == expected
        and all(event["completed"] and event["direction"] == direction for event in events),
    }
