#include "test_support.h"
#ifdef ISAAC_LAN_TEST_REPENTANCE
#include "engine/versions/repentance/smelted_trinkets.h"
namespace backend = isaac::engine::repentance;
inline constexpr unsigned vectorOffset = 0x1670;
#else
#include "engine/versions/repentance_plus/smelted_trinkets.h"
namespace backend = isaac::engine::repentance_plus;
inline constexpr unsigned vectorOffset = 0x1748;
#endif
#include <array>
#include <cstdio>

int main() {
    try {
        using namespace backend;
        using namespace smelted_trinkets;
        std::array<std::uint8_t, 0x2200> playerBytes{};
        std::array<Counts, 191> counts{};
        const auto player = reinterpret_cast<Address>(playerBytes.data());
        auto* vector = reinterpret_cast<Address*>(player + vectorOffset);
        vector[0] = reinterpret_cast<Address>(counts.data());
        vector[1] = vector[2] = reinterpret_cast<Address>(counts.data() + counts.size());
        const auto originalPlayer = playerBytes;
        const State desired{{39, {2, 1}}, {83, {0, 1}}, {190, {32767, 32767}}};
        require(restore(player, desired) && capture(player) == desired,
                "Normal/golden swallowed counts did not round trip");
        require(counts[39] == Counts{2, 1} && counts[83] == Counts{0, 1} && counts[1] == Counts{},
                "Swallowed counters were written to the wrong IDs");
        require(!restore(player, desired) && playerBytes == originalPlayer,
                "Repeated state changed inventory or native vector ownership");
        for (auto invalid : {State{{39, {1, 0}}, {191, {1, 0}}}, State{{39, {1, 0}}, {39, {2, 0}}},
                             State{{0, {1, 0}}}, State{{83, {1, 0}}, {39, {1, 0}}},
                             State{{39, {-1, 0}}}, State{{39, {0, -1}}}, State{{39, {0, 0}}}}) {
            const auto before = counts;
            bool rejected = false;
            try {
                restore(player, invalid);
            } catch (const std::runtime_error&) {
                rejected = true;
            }
            require(rejected && counts == before && playerBytes == originalPlayer,
                    "Invalid state partially changed native inventory");
        }
        require(restore(player, {{39, {1, 0}}}) && counts[83] == Counts{} &&
                    counts[190] == Counts{} && counts[39] == Counts{1, 0},
                "Rollback retained obsolete swallowed effects");
        require(restore(player, {}) && capture(player).empty() && !restore(player, {}),
                "Empty inventory did not clear persistent effects exactly once");
        vector[1] = vector[0] + 1;
        bool rejected = false;
        try {
            capture(player);
        } catch (const std::runtime_error&) {
            rejected = true;
        }
        require(rejected, "Misaligned native vector was accepted");
        vector[0] = vector[1] = vector[2] = 0;
        require(capture(player).empty() && !restore(player, {}), "Empty native vector failed");
        std::puts("PASS native swallowed counts, golden duplicates, rollback and validation");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
