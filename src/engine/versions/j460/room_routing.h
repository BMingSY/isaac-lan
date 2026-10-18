#pragma once
#include <cstdint>
#include <functional>

namespace isaac::engine::j460 {
struct RoomArrival {
    int index, dimension, door;
    bool redirected;
};
// Synchronous, main-thread-only boundary inside Level::ChangeRoom. The callback
// installs the final native room; false skips initialization of an occupied room.
// No game objects or callback survive the native call; exceptions unwind in C++.
void withResolvedRoomEntry(const std::function<bool(RoomArrival)>& prepare,
                           const std::function<void()>& change);
void withoutRoomCurseRouting(const std::function<void()>& change);
std::uint32_t currentCurses();
bool installRoomRouting(std::uintptr_t image);
} // namespace isaac::engine::j460
