#include "test_support.h"
#include "engine/versions/j511/layout.h"
#include "engine/versions/j835/layout.h"
#include <algorithm>
#include <array>

namespace {
void check(const isaac::engine::native_progress::Layout& layout, unsigned achievements,
           unsigned count, unsigned counters, bool ordinal = false) {
    using namespace isaac::engine;
    alignas(unsigned) std::array<std::uint8_t, 4096> memory;
    memory.fill(0x5a);
    isaac::lan::Progress source;
    source.achievements.fill(1);
    for (unsigned i = 0; i < source.counters.size(); ++i)
        source.counters[i] = ordinal && native_completion::bitCounters[i]
                                 ? std::array<unsigned, 3>{0, 1, 3}[i % 3]
                                 : i + 1000;
    const auto address = reinterpret_cast<std::uintptr_t>(memory.data());
    native_progress::write(address, layout, source);
    // This expected image uses the independently audited native array bounds.
    auto expected = memory;
    expected.fill(0x5a);
    std::fill_n(expected.begin() + 0x38, achievements, 1);
    std::memcpy(expected.data() + counters, source.counters.data(), count * sizeof(unsigned));
    if (ordinal)
        for (unsigned i = 0; i < count; ++i)
            if (native_completion::bitCounters[i]) {
                const unsigned nativeRank = i % 3;
                std::memcpy(expected.data() + counters + i * sizeof(unsigned), &nativeRank,
                            sizeof(nativeRank));
            }
    require(memory == expected, "Native progression write crossed its array bounds");
    const auto restored = native_progress::read(address, layout);
    for (unsigned i = 0; i < restored.achievements.size(); ++i)
        require(restored.achievements[i] == (i < achievements ? 1 : 0),
                "Missing native achievements must be zero-filled on the wire");
    for (unsigned i = 0; i < restored.counters.size(); ++i)
        require(restored.counters[i] == (i < count ? source.counters[i] : 0),
                "Missing native counters must be zero-filled on the wire");
    require(memory == expected, "Reading progression mutated native state");
}
void j511() {
    check(isaac::engine::j511::layout::progress::fields, 642, 523, 0x2bc);
}
void j835() {
    check(isaac::engine::j835::layout::progress::fields, 638, 496, 0x2b8, true);
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"j511", j511}, {"j835", j835}});
}
