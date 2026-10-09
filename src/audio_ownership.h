#pragma once
#include <array>
#include <cstdint>

namespace isaac::audio {
using RoomKey = std::array<std::int32_t, 3>;
inline RoomKey audioRoomKey(unsigned epoch, int dimension, int room) {
    return {static_cast<std::int32_t>(epoch), dimension, room};
}
inline bool audible(unsigned audience, int localSlot) {
    return !audience || (localSlot >= 0 && localSlot < 4 && (audience & (1u << localSlot)));
}
} // namespace isaac::audio
