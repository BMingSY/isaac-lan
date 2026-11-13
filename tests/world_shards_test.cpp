#include "net/world_shards.h"
#include "net/world_redundancy.h"
#include "test_support.h"
#include <random>

using namespace isaac::lan;
static void erasures() {
    std::mt19937 random(103);
    for (const auto size : {1u, 1023u, 1200u, 2048u, 3072u, 3073u, 8192u, 88001u, 2097152u}) {
        std::vector<std::uint8_t> input(size);
        for (auto& byte : input)
            byte = random();
        std::vector<std::vector<std::uint8_t>> packets;
        WorldShards::send(1, input, [&](auto packet) {
            require(packet.size() <= WorldShards::shardSize + 11, "Shard exceeds MTU budget");
            packets.emplace_back(packet.begin(), packet.end());
        });
        // Every pair of erased data/parity positions, including partial groups.
        for (unsigned first = 0; first < 10; ++first) {
            for (unsigned second = first + 1; second < 10; ++second) {
                WorldShards receiver;
                std::optional<std::vector<std::uint8_t>> output;
                auto shuffled = packets;
                std::shuffle(shuffled.begin(), shuffled.end(), random);
                for (const auto& packet : shuffled) {
                    const auto group = (packet[8] << 8) | packet[9];
                    const auto count = std::min<std::size_t>(8, (size + 1023) / 1024 - group * 8);
                    const auto index = packet[10];
                    // Views up to three shards and single-data tail groups
                    // tolerate one erasure; larger groups tolerate two.
                    if (index == first || (size > 3072 && count > 1 && index == second))
                        continue;
                    if (auto value = receiver.receive(packet))
                        output = std::move(value);
                    require(!receiver.receive(packet), "Duplicate shard completed twice");
                }
                require(output && *output == input, "Erasure recovery changed complete bytes");
            }
        }
    }
}
static void overhead() {
    for (const auto& [size, count] :
         {std::pair{1200u, 3u}, {2048u, 3u}, {3072u, 4u}, {3073u, 6u}, {8192u, 10u}}) {
        std::vector<std::uint8_t> bytes(size, 42);
        std::size_t packets = 0, wire = 0;
        WorldShards::send(1, bytes, [&](auto packet) {
            ++packets;
            wire += packet.size();
        });
        require(packets == count && packets == WorldShards::packetCount(size),
                "Small-view parity or sequence-window packet budget differs");
        if (size <= 3072)
            require(wire == size + 1024 + count * 11, "Small view sent redundant second parity");
    }
}
static void cleanup() {
    std::vector<std::uint8_t> input(88001, 42);
    WorldShards receiver;
    for (unsigned tick = 1; tick < 200; ++tick) {
        bool first = true;
        WorldShards::send(tick, input, [&](auto packet) {
            if (first)
                require(!receiver.receive(packet), "Incomplete view escaped");
            first = false;
        });
        require(receiver.buffered() <= WorldShards::maxBuffered, "Partial views grew unbounded");
    }
    unsigned delivered = 0;
    WorldShards::send(200, input, [&](auto packet) {
        if (auto result = receiver.receive(packet)) {
            require(*result == input, "Newer view corrupted");
            ++delivered;
        }
    });
    require(delivered == 1 && receiver.buffered() == 0, "Completion retained obsolete work");
    WorldShards::send(1, input, [&](auto packet) {
        require(!receiver.receive(packet), "Old shards regressed completed view");
    });
    receiver.reset();
    WorldShards::send(0, input, [&](auto packet) {
        if (receiver.receive(packet))
            ++delivered;
    });
    require(delivered == 2, "Generation reset retained old tick ordering");
    std::vector<std::vector<std::uint8_t>> packets;
    WorldShards::send(2, input,
                      [&](auto packet) { packets.emplace_back(packet.begin(), packet.end()); });
    auto malformed = packets.front();
    malformed.pop_back();
    rejects([&] { receiver.receive(malformed); }, "Short shard accepted");
    malformed = packets.front();
    malformed[10] = 10;
    rejects([&] { receiver.receive(malformed); }, "Invalid shard accepted");
}
static void adaptive() {
    using namespace std::chrono_literals;
    WorldRedundancy policy;
    auto now = WorldRedundancy::Clock::time_point{};
    require(policy.parity(now) == 2, "Unknown path lost its conservative redundancy");
    for (unsigned report = 0; report <= 6; ++report) {
        policy.observe({report * 15, 0, 0}, now + report * 500ms);
        if (report < 6)
            require(policy.parity(now + report * 500ms) == 2, "Parity fell before clean evidence");
    }
    require(policy.parity(now + 3s) == 1, "Clean path never reduced redundant traffic");
    require(policy.parity(now + 5s) == 2, "Stale feedback retained weak protection");
    policy.observe({91, 1, 0}, now + 3500ms);
    require(policy.parity(now + 3500ms) == 2,
            "A repaired view failed to restore two parity shards");
    policy.observe({90, 0, 0}, now + 3600ms);
    require(policy.parity(now + 3600ms) == 2, "Reordered feedback erased loss evidence");
    for (unsigned report = 1; report <= 6; ++report)
        policy.observe({91 + report * 15, 1, 0}, now + 3500ms + report * 500ms);
    require(policy.parity(now + 6500ms) == 1, "Recovered path could not reduce redundancy again");
    policy.observe({182, 1, 1}, now + 7s);
    require(policy.parity(now + 7s) == 2, "Discarded incomplete view was ignored");
    rejects([&] { policy.observe({1, 2, 0}, now); }, "Invalid quality accepted");
    std::vector<std::uint8_t> bytes(88001, 42);
    WorldShards receiver;
    std::size_t packets = 0;
    WorldShards::send(
        1, bytes,
        [&](auto packet) {
            ++packets;
            if (packet[10] == 0)
                return; // One erased data shard in every group, with only one parity.
            if (auto result = receiver.receive(packet))
                require(*result == bytes, "Adaptive parity changed decoded bytes");
        },
        1);
    require(packets == WorldShards::packetCount(bytes.size(), 1) &&
                packets < WorldShards::packetCount(bytes.size()),
            "Reduced parity saved no packets");
    require(receiver.quality.completed == 1 && receiver.quality.repaired == 1,
            "Receiver did not report successful parity recovery");
    WorldShards::send(2, bytes, [&](auto packet) {
        if (packet[10] == 0)
            receiver.receive(packet);
    });
    WorldShards::send(3, bytes, [&](auto packet) { receiver.receive(packet); });
    require(receiver.quality.completed == 2 && receiver.quality.repaired == 1 &&
                receiver.quality.discarded == 1,
            "Incomplete obsolete views were not counted");
    receiver.reset();
    require(!receiver.quality.completed && !receiver.quality.repaired &&
                !receiver.quality.discarded,
            "Floor reset retained quality from an old generation");
}
int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"erasures", erasures},
                     {"cleanup", cleanup},
                     {"overhead", overhead},
                     {"adaptive", adaptive}});
}
