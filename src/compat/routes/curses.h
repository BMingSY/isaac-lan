#pragma once
#include <cstdint>

namespace isaac::compat::routes {
// A replica receives a room destination already selected by the host. Keep
// the shared curse, but do not run Maze's random routing a second time during
// native entry. Restore only Maze so unrelated entry effects retain changes.
class ResolvedRoomCurses {
    static constexpr std::uint32_t maze = 1u << 5;
    std::uint32_t& base;
    std::uint32_t& seeds;
    std::uint32_t savedBase, savedSeeds;
    bool replica;

  public:
    ResolvedRoomCurses(std::uint32_t& base, std::uint32_t& seeds, bool replica)
        : base(base), seeds(seeds), savedBase(base & maze), savedSeeds(seeds & maze),
          replica(replica) {
        if (replica) {
            base &= ~maze;
            seeds &= ~maze;
        }
    }
    ResolvedRoomCurses(const ResolvedRoomCurses&) = delete;
    ResolvedRoomCurses& operator=(const ResolvedRoomCurses&) = delete;
    ~ResolvedRoomCurses() {
        if (replica) {
            base = (base & ~maze) | savedBase;
            seeds = (seeds & ~maze) | savedSeeds;
        }
    }
};
} // namespace isaac::compat::routes
