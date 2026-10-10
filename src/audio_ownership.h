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
inline bool continueRoomTrack(RoomKey previous, RoomKey next, int requested,
                              std::array<unsigned, 2> channels) {
    // Room ownership changes independently of the physical music channels.
    // Preserve a running track unless a different track or queued jingle is
    // taking over. A new floor still follows its native music selection.
    return previous != next && previous[0] == next[0] && requested > 0 &&
           channels[0] == static_cast<unsigned>(requested) && channels[1] == 0;
}
} // namespace isaac::audio
