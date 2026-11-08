#include "core/input_latency.h"
#include "net/latency.h"
#include "test_support.h"
#include <chrono>

using namespace std::chrono_literals;
namespace {
void acknowledgements() {
    isaac::core::InputLatency latency;
    const auto start = std::chrono::steady_clock::time_point{};
    latency.capture(1, start);
    require(latency.present(1, start + 8ms) == 8 && !latency.present(1, start + 16ms),
            "Presentation duplicated one input sample");
    require(latency.confirm(1, start + 90ms) == 90 && !latency.confirm(1, start + 100ms),
            "Repeated acknowledgement refreshed latency");
    latency.capture(2, start + 20ms);
    latency.capture(3, start + 40ms);
    require(latency.confirm(3, start + 160ms) == 120 && !latency.confirm(2, start + 170ms),
            "Coalesced/reordered inputs measured the wrong sample");
    latency.capture(4, start + 60ms);
    latency.capture(132, start + 1s);
    require(!latency.present(4, start + 1s) && !latency.confirm(4, start + 1s),
            "Evicted input was mistaken for a newer sample");
    require(latency.confirm(132, start + 1200ms) == 200,
            "New acknowledgement did not recover after a stall");
    latency = {};
    require(!latency.confirm(132, start + 2s), "Reset retained an old timestamp");
    latency = {};
    latency.capture(1, start + 2s);
    require(latency.confirm(1, start + 2040ms) == 40,
            "New input stream retained the previous acknowledgement");
}
void freshness() {
    using namespace isaac::lan;
    const auto start = LatencySample::Clock::time_point{};
    LatencySample sample;
    require(sample.value(start) == -1, "Unmeasured latency appeared valid");
    sample.record(50, start);
    require(sample.value(start + 2999ms) == 50 && sample.value(start + 3s) == -1,
            "Latency did not expire without a fresh measurement");
    Writer report(Message::latency);
    sample.write(report, start + 2s);
    Reader reader(std::span<const std::uint8_t>(report.bytes).subspan(1));
    auto remote = LatencySample::read(reader, start + 10s);
    reader.finish();
    require(remote.value(start + 10999ms) == 50 && remote.value(start + 11s) == -1,
            "Forwarding an aged sample restarted its lifetime");
    Writer relay(Message::latency);
    remote.write(relay, start + 10500ms);
    Reader relayed(std::span<const std::uint8_t>(relay.bytes).subspan(1));
    auto second = LatencySample::read(relayed, start + 20s);
    require(second.value(start + 20499ms) == 50 && second.value(start + 20500ms) == -1,
            "Second relay refreshed an old measurement");
    Writer expired(Message::latency);
    sample.write(expired, start + 4s);
    Reader stale(std::span<const std::uint8_t>(expired.bytes).subspan(1));
    require(LatencySample::read(stale, start + 20s).value(start + 20s) == -1,
            "Expired sample survived encoding");
    sample.record(0, start);
    require(sample.value(start) == 0, "Zero milliseconds was treated as unknown");
    sample.record(100000, start);
    require(sample.value(start) == LatencySample::maximum, "Large sample overflowed the wire");
    sample.record(-1, start);
    require(sample.value(start) == -1, "Unknown sample retained a previous value");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"acknowledgements", acknowledgements}, {"freshness", freshness}});
}
