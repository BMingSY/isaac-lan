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
inline unsigned roomEntryTrack(std::array<unsigned, 2> request) {
    // A listener entering a room joins its ongoing track. Intro/outro requests
    // belong to listeners who were present when that request occurred.
    return request[1] ? request[1] : request[0];
}
inline bool continueRoomTrack(RoomKey previous, RoomKey next, std::array<unsigned, 2> requested,
                              std::array<unsigned, 2> channels) {
    // Room ownership changes independently of the physical music channels.
    // Preserve a running track unless a different track or queued jingle is
    // taking over. A new floor still follows its native music selection.
    return previous != next && previous[0] == next[0] && requested[0] > 0 && requested[1] == 0 &&
           channels == requested;
}
inline bool completedQueuedTrack(std::array<unsigned, 2> previous,
                                 std::array<unsigned, 2> requested,
                                 std::array<unsigned, 2> channels) {
    return previous[1] != 0 && requested[0] == previous[1] && requested[1] == 0 &&
           channels == requested;
}
} // namespace isaac::audio
