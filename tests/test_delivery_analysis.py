import pytest

from testing.delivery import analyze_delivery, time_weighted_age


def test_time_weighted_age_includes_stalled_delivery():
    continuous = time_weighted_age([(50, 100)] * 5)
    stalled = time_weighted_age([(50, 500)])
    assert continuous["mean"] == 100 and continuous["p95"] == 145
    assert stalled["mean"] == 300 and stalled["p95"] == 525
    assert continuous["duration_ms"] == stalled["duration_ms"] == 500


def test_delivery_analysis_pairs_original_ticks_and_rejects_missing_evidence():
    host = "WEAK_TCP VIEW tick=60 ms=1000\nWEAK_TCP VIEW tick=63 ms=1100\n"
    client = "WEAK_NET APPLY tick=60 ms=1050\nWEAK_NET APPLY tick=63 ms=1150\n"
    result = analyze_delivery(host, client, minimum_samples=2)
    assert result["arrival_age_ms"]["mean"] == 50
    assert result["view_age_ms"]["p95"] == 145
    with pytest.raises(ValueError, match="Incomplete"):
        analyze_delivery(host, client)
    with pytest.raises(ValueError, match="source timestamp"):
        analyze_delivery(host.replace("tick=63", "tick=64"), client, minimum_samples=2)
    with pytest.raises(ValueError, match="Non-monotonic"):
        analyze_delivery(host, client + client, minimum_samples=2)
    with pytest.raises(ValueError, match="invalid delivery"):
        analyze_delivery(host.replace("ms=1000", "ms=2000"), client, minimum_samples=2)
