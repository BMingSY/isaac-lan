import pytest

from benchmark_compression import ALGORITHMS, summarize


def measurements():
    return [
        {
            "algorithm": algorithm,
            "players": players,
            "samples": 10,
            "raw_bytes": 1000,
            "packed_bytes": 100,
            "encode": {"mean_ms": 1, "p95_ms": 2, "p99_ms": 3},
            "decode": {"mean_ms": 1, "p95_ms": 2, "p99_ms": 3},
        }
        for algorithm in ALGORITHMS
        for players in (2, 3, 4)
    ]


def test_compression_report_requires_every_algorithm_and_peer_count():
    rows = measurements()
    assert summarize(rows, 10) == rows
    with pytest.raises(ValueError):
        summarize(rows[:-1], 10)
    with pytest.raises(ValueError):
        summarize([*rows, rows[0]], 10)
    with pytest.raises(ValueError):
        summarize(rows, 11)


@pytest.mark.parametrize("key,value", [("samples", 0), ("packed_bytes", 0), ("raw_bytes", -1)])
def test_empty_measurement_cannot_pass(key, value):
    rows = measurements()
    rows[0][key] = value
    with pytest.raises(ValueError):
        summarize(rows, 10)
