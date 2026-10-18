#pragma once
#include <cstdint>

namespace isaac::compat::routes {
inline constexpr std::uint32_t mazeCurse = 1u << 5;
inline bool resolveRoomCurse(bool replica, bool resolved, std::uint32_t curses) {
    // Native routing decides room/dimension eligibility, including special-room
    // exits that restore a different origin before evaluating Maze.
    return !replica && !resolved && (curses & mazeCurse);
}
// Native content swaps assume that their saved rooms have no live occupants.
// Split-room play must keep a teammate's active objects and descriptor together.
inline bool allowCurseRoomSwap(bool firstActive, bool secondActive) {
    return !firstActive && !secondActive;
}
// A received/restored destination must bypass the whole native Maze branch,
// including permanent seed curses. Other curses and RNG state remain untouched.
class ResolvedRoomCurses {
    bool& suppressed;
    bool previous;

  public:
    explicit ResolvedRoomCurses(bool& suppressed) : suppressed(suppressed), previous(suppressed) {
        suppressed = true;
    }
    ResolvedRoomCurses(const ResolvedRoomCurses&) = delete;
    ResolvedRoomCurses& operator=(const ResolvedRoomCurses&) = delete;
    ~ResolvedRoomCurses() {
        suppressed = previous;
    }
};
} // namespace isaac::compat::routes
