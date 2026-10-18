import pytest
from benchmark_state_codec import summarize


def measurement(implementation, **changes):
    return {
        "case": "inventory",
        "operation": "encode",
        "implementation": implementation,
        "bytes": 1024,
        "samples": 100,
        "mean_ms": 2.0,
        "p95_ms": 3.0,
        **changes,
    }


def test_benchmark_compares_matching_completed_workloads():
    results = summarize([measurement("lua"), measurement("native", mean_ms=0.5)])
    assert results[0]["speedup"] == 4
    assert results[0]["lua"]["samples"] == results[0]["native"]["samples"] == 100


@pytest.mark.parametrize(
    "samples",
    [
        [],
        [measurement("lua")],
        [measurement("lua"), measurement("lua"), measurement("native")],
        [measurement("lua"), measurement("native", bytes=512)],
        [measurement("lua"), measurement("native", samples=99)],
        [measurement("lua"), measurement("native", mean_ms=-1)],
    ],
)
def test_partial_or_mismatched_benchmarks_cannot_pass(samples):
    with pytest.raises(ValueError):
        summarize(samples)
