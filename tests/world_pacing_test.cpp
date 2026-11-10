#include "net/world_pacing.h"
#include "test_support.h"
#include <deque>

using namespace isaac::lan;
using namespace std::chrono_literals;
using Clock = WorldPacing::Clock;

static void budget() {
    WorldPacing pacing;
    const auto start = Clock::time_point{};
    require(pacing.consume(1200, start) && pacing.consume(1200, start) &&
                !pacing.consume(1200, start),
            "Realtime budget allowed an unbounded initial burst");
    require(pacing.consume(1200, start + 10ms), "Realtime budget never replenished");
    require(pacing.consume(1200, start + 10s) && pacing.consume(1200, start + 10s) &&
                !pacing.consume(1200, start + 10s),
            "Idle time accumulated stale burst credit");
    pacing.reserve(32768, start + 10s);
    require(!pacing.ready(1200, start + 10s + 5ms), "Recovery retry bypassed path debt");
    require(!pacing.consume(1200, start + 10s + 5ms), "Recovery bytes did not occupy the path");
    require(pacing.consume(1200, start + 11s), "Reliable recovery starved realtime indefinitely");
    pacing = {};
    require(pacing.consume(1200, start), "Generation reset retained old debt");
}

static void feedback() {
    WorldPacing pacing;
    auto now = Clock::time_point{};
    const auto initial = pacing.bytesPerSecond();
    pacing.acknowledge(1200, 95, 90, now);
    now += 50ms;
    pacing.acknowledge(1200, 300, 300, now);
    require(pacing.bytesPerSecond() == initial,
            "An isolated delayed ACK was treated as congestion");
    for (unsigned i = 0; i < 4; ++i) {
        now += 50ms;
        pacing.acknowledge(1200, 300, 300, now);
    }
    require(pacing.bytesPerSecond() < initial, "Queue growth did not reduce publication rate");
    const auto reduced = pacing.bytesPerSecond();
    for (unsigned i = 0; i < 100; ++i)
        pacing.acknowledge(1200, 300, 300, now);
    require(pacing.bytesPerSecond() == reduced, "ACK burst multiplied congestion penalties");
    for (unsigned i = 0; i < 40; ++i) {
        now += 250ms;
        pacing.congested(now);
    }
    require(pacing.bytesPerSecond() >= WorldPacing::minimumRate,
            "Blackout removed recovery budget");
    const auto stalled = pacing.bytesPerSecond();
    for (unsigned i = 0; i < 20; ++i) {
        now += 250ms;
        pacing.acknowledge(1200, 95, 90, now);
    }
    require(pacing.bytesPerSecond() > stalled * 4, "Healthy delivery never recovered capacity");
    require(pacing.bytesPerSecond() <= WorldPacing::maximumRate, "Rate exceeded its bound");

    // Alternating 10/55 ms relay legs produce occasional 110 ms receipts on
    // an uncongested link. They must not ratchet capacity down to the minimum.
    pacing = {};
    for (unsigned i = 0; i < 300; ++i) {
        now += 33ms;
        const auto latency = i % 3 == 0 ? 110 : 20;
        pacing.acknowledge(1200, latency, latency, now);
    }
    require(pacing.bytesPerSecond() >= initial, "Ordinary jitter collapsed the send budget");
}

static void pathChanges() {
    WorldPacing pacing;
    auto now = Clock::time_point{};
    pacing.acknowledge(1200, 95, 90, now);
    // The transport remains healthy while the game thread takes 300 ms to
    // apply each view. Application delay must not masquerade as a full path.
    for (unsigned i = 0; i < 120; ++i) {
        now += 33ms;
        pacing.acknowledge(1200, 390, 90, now);
    }
    require(pacing.bytesPerSecond() >= WorldPacing::initialRate,
            "Slow application collapsed the transport budget");
    // A new route has a higher base RTT, without growing queues. Forget the
    // obsolete minimum, then regain capacity rather than remaining at 16 KiB/s.
    pacing = {};
    pacing.acknowledge(1200, 95, 90, now);
    for (unsigned i = 0; i < 300; ++i) {
        now += 33ms;
        pacing.acknowledge(1200, 185, 180, now);
    }
    require(pacing.bytesPerSecond() >= WorldPacing::initialRate,
            "A stable route change permanently throttled publication");
}

static void bottleneck() {
    // A FIFO 32 KiB/s path, 90 ms base RTT and a 500 ms queue limit. The
    // producer always has fresh data; transport credit must prevent sustained
    // overload without needing a test-only bandwidth setting in production.
    WorldPacing pacing;
    struct Receipt {
        double at, sent;
    };
    std::deque<Receipt> receipts;
    double available = 0, delay = 0;
    unsigned delivered = 0;
    const auto origin = Clock::time_point{};
    for (unsigned step = 0; step < 3000; ++step) {
        const double seconds = step * 0.005;
        const auto now = origin + std::chrono::milliseconds(step * 5);
        while (!receipts.empty() && receipts.front().at <= seconds) {
            const auto receipt = receipts.front();
            receipts.pop_front();
            const auto latency = (receipt.at - receipt.sent) * 1000;
            pacing.acknowledge(1200, latency, static_cast<int>(latency), now);
            if (seconds >= 10) {
                delay += receipt.at - receipt.sent;
                ++delivered;
            }
        }
        for (unsigned packet = 0; packet < 16 && pacing.consume(1200, now); ++packet) {
            if (available - seconds > 0.5)
                continue;
            available = std::max(available, seconds) + 1200.0 / 32768;
            receipts.push_back({available + 0.09, seconds});
        }
    }
    std::printf("PACED 32KiB/s delivered=%u mean_rtt_ms=%.1f rate=%.0f\n", delivered,
                delay * 1000 / delivered, pacing.bytesPerSecond());
    require(delivered > 60, "Congestion recovery left the path idle");
    require(delay / delivered < 0.2, "Realtime pacing retained excessive queue delay");
}

int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"budget", budget},
                     {"feedback", feedback},
                     {"bottleneck", bottleneck},
                     {"path-changes", pathChanges}});
}
