#include "net/world_shards.h"
#include "test_support.h"
#include <random>

using namespace isaac::lan;
static void erasures() {
    std::mt19937 random(103);
    for (const auto size : {1u, 1023u, 2048u, 8192u, 88001u, 2097152u}) {
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
                    // Single-data groups carry one parity and tolerate one loss.
                    if (index == first || (count > 1 && index == second))
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
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"erasures", erasures}, {"cleanup", cleanup}});
}
