#pragma once
#include "net/protocol.h"

namespace isaac::input {
inline bool menuActionTriggered(const lan::InputFrame& input, int action) {
    if (action >= 0 && action < 16)
        return (input.triggered & (1u << action)) != 0;
    if (action >= 20 && action <= 23) {
        const auto direction = static_cast<unsigned>(action - 20);
        return (input.triggered & ((1u << direction) | (1u << (direction + 4)))) != 0;
    }
    return false;
}
inline lan::InputFrame transitionInput(const lan::InputFrame& input, bool sameFloor) {
    auto result = lan::menuInput(input);
    // Stop stale movement/items until the guest sees the destination. Releasing
    // held fire here would discharge Brimstone and other charged weapons.
    if (sameFloor)
        for (unsigned action = 4; action < 8; ++action)
            result.values[action] = input.values[action];
    return result;
}
inline void captureRoomInput(lan::InputFrame& input, std::optional<lan::InputRoom>& room,
                             std::optional<lan::InputRoom>& previous, std::uint32_t epoch) {
    if (room) {
        previous = room;
        return;
    }
    // Room::Init can poll the frontend while the roster is temporarily scoped.
    // Keep held fire tied to the last stable room, never to a different floor.
    const bool sameFloor = previous && previous->epoch == epoch;
    if (sameFloor)
        room = previous;
    input = transitionInput(input, sameFloor);
}
inline void keyboardPause(lan::InputFrame& input, bool paused) {
    // J460 accepts keyboard Escape as MENU_BACK only on controller zero.
    // LAN actors use controllers 1..4, whose pause entry requires MENU_PAUSE.
    // Keep Back unchanged inside a menu so its native navigation still works.
    if (!paused && (input.triggered & (1u << 15))) {
        input.triggered |= 1u << 12;
        input.values[12] = 65535;
    }
}
inline lan::InputFrame pausedInput(const lan::InputFrame& input) {
    lan::InputFrame result;
    // Menu navigation stays local. Keep held fire for charged weapons across
    // the authoritative resume boundary, without forwarding item/button edges.
    for (unsigned action = 4; action < 8; ++action)
        result.values[action] = input.values[action];
    return result;
}
} // namespace isaac::input
