#include "core/snapshot_delta.h"
#include "test_support.h"
#include <random>

using isaac::core::SnapshotDelta;
namespace {
std::vector<std::uint8_t> noise(std::size_t size, unsigned seed = 17) {
    std::mt19937 random(seed);
    std::vector<std::uint8_t> bytes(size);
    for (auto& byte : bytes)
        byte = static_cast<std::uint8_t>(random());
    return bytes;
}
void changes() {
    auto base = noise(140000);
    for (unsigned seed = 0; seed < 40; ++seed) {
        auto value = base;
        std::mt19937 random(seed);
        for (unsigned i = 0; i < 200; ++i)
            value[random() % value.size()] ^= static_cast<std::uint8_t>(random());
        const auto at = random() % 60000;
        value.erase(value.begin() + at, value.begin() + at + 733);
        const auto inserted = noise(1000, seed);
        value.insert(value.begin() + 90000, inserted.begin(), inserted.end());
        const auto patch = SnapshotDelta::encode(base, value);
        require(patch && patch->size() < value.size() / 8,
                "Sparse changes and shifted objects were not compacted");
        require(SnapshotDelta::apply(base, *patch) == value,
                "Inserted/deleted bytes changed reconstructed state");
    }
    for (const auto& base :
         {noise(SnapshotDelta::limit), std::vector<std::uint8_t>(SnapshotDelta::limit, 0)}) {
        const auto patch = SnapshotDelta::encode(base, base);
        require(patch && patch->size() < 64 && SnapshotDelta::apply(base, *patch) == base,
                "Repeated maximum-sized state did not round trip");
    }
    require(!SnapshotDelta::encode(noise(16000, 1), noise(16000, 2)),
            "Incompressible delta did not fall back to a full state");
    require(!SnapshotDelta::encode({base.data(), 8}, {base.data(), 8}),
            "Tiny state paid more for a delta than its full payload");
}
void validation() {
    const auto base = noise(4096);
    const auto patch = SnapshotDelta::encode(base, base);
    require(patch.has_value(), "Repeated state patch is missing");
    for (std::size_t size = 0; size < patch->size(); ++size)
        rejects([&] { SnapshotDelta::apply(base, std::span(*patch).first(size)); },
                "Truncated patch was accepted");
    for (std::size_t offset = 0; offset < patch->size(); ++offset) {
        auto broken = *patch;
        broken[offset] ^= 128;
        rejects([&] { SnapshotDelta::apply(base, broken); }, "Corrupted patch was accepted");
    }
    auto wrong = base;
    wrong.back() ^= 1;
    rejects([&] { SnapshotDelta::apply(wrong, *patch); }, "Wrong baseline was accepted");
    auto trailing = *patch;
    trailing.push_back(0);
    rejects([&] { SnapshotDelta::apply(base, trailing); }, "Trailing data was accepted");
    rejects([&] { SnapshotDelta::encode({}, base); }, "Empty baseline was accepted");
    rejects([&] { SnapshotDelta::encode(base, {}); }, "Empty state was accepted");
    const std::vector<std::uint8_t> large(SnapshotDelta::limit + 1);
    rejects([&] { SnapshotDelta::encode(base, large); }, "Oversized state was accepted");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"changes", changes}, {"validation", validation}});
}
