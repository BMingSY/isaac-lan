"""Measure same-machine TCP view freshness from the weak-network fixture."""

import math
import re


def distribution(values):
    ordered = sorted(values)
    if not ordered or any(not math.isfinite(value) or value < 0 for value in ordered):
        raise ValueError("Missing or invalid delivery measurements")
    return {
        "samples": len(ordered),
        "mean": round(sum(ordered) / len(ordered), 3),
        "p95": round(ordered[math.ceil(len(ordered) * 0.95) - 1], 3),
        "max": round(ordered[-1], 3),
    }


def time_weighted_age(intervals):
    """Age keeps increasing between arrivals; skipped updates cannot hide gaps."""
    if not intervals or any(age < 0 or duration <= 0 for age, duration in intervals):
        raise ValueError("Missing or invalid delivery intervals")
    elapsed = sum(duration for _, duration in intervals)
    maximum = max(age + duration for age, duration in intervals)

    def percentile(fraction):
        low, high = 0, maximum
        for _ in range(40):
            middle = (low + high) / 2
            below = sum(min(duration, max(0, middle - age)) for age, duration in intervals)
            if below < elapsed * fraction:
                low = middle
            else:
                high = middle
        return round(high, 3)

    return {
        "duration_ms": elapsed,
        "mean": round(
            sum(age * duration + duration * duration / 2 for age, duration in intervals) / elapsed,
            3,
        ),
        "p95": percentile(0.95),
        "p99": percentile(0.99),
        "max": round(maximum, 3),
    }


def analyze_delivery(host_log, client_log, *, minimum_samples=100):
    sources = {}
    for tick, timestamp in re.findall(r"WEAK_TCP VIEW tick=(\d+) ms=([\d.]+)", host_log):
        tick, timestamp = int(tick), float(timestamp)
        if tick in sources and sources[tick] != timestamp:
            raise ValueError("Conflicting source timestamps for one view")
        sources[tick] = timestamp
    applied = [
        (int(tick), float(timestamp))
        for tick, timestamp in re.findall(r"WEAK_TCP APPLY tick=(\d+) ms=([\d.]+)", client_log)
    ]
    applied = [(tick, timestamp) for tick, timestamp in applied if tick >= 60]
    if len(applied) < minimum_samples:
        raise ValueError("Incomplete TCP delivery evidence")
    if any(b[0] <= a[0] or b[1] <= a[1] for a, b in zip(applied, applied[1:])):
        raise ValueError("Non-monotonic applied state evidence")
    if any(tick not in sources for tick, _ in applied):
        raise ValueError("Applied state lacks a source timestamp")
    ages = [timestamp - sources[tick] for tick, timestamp in applied]
    gaps = [b[1] - a[1] for a, b in zip(applied, applied[1:])]
    return {
        "received_states": len(applied),
        "arrival_age_ms": distribution(ages),
        "update_gap_ms": distribution(gaps),
        "view_age_ms": time_weighted_age(list(zip(ages, gaps))),
    }
