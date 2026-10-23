#pragma once
#include "net/protocol.h"

namespace isaac::input {
class ModalInput {
    std::uint16_t held = 0;
    bool pointerHeld = false;

  public:
    void filter(lan::InputFrame& input, bool capturing) {
        pointerHeld = input.pointer.active && (capturing || pointerHeld);
        std::uint16_t down = input.triggered;
        for (unsigned action = 0; action < lan::actionCount; ++action)
            if (input.values[action])
                down |= 1u << action;
        held = capturing ? down : held & down;
        if (capturing) {
            input = {};
            return;
        }
        for (unsigned action = 0; action < lan::actionCount; ++action)
            if (held & (1u << action))
                input.values[action] = 0;
        input.triggered &= ~held;
        if (pointerHeld)
            input.pointer = {};
    }
};
inline bool menuActionTriggered(const lan::InputFrame& input, int button) {
    if (button >= 0 && button < static_cast<int>(lan::actionCount))
        return (input.triggered & (1u << button)) != 0;
    if (button >= action::menuLeft && button <= action::menuDown) {
        const auto direction = static_cast<unsigned>(button - action::menuLeft);
        return (input.triggered & ((1u << direction) | (1u << (direction + action::shootLeft)))) !=
               0;
    }
    return false;
}
inline lan::InputFrame transitionInput(const lan::InputFrame& input, bool sameFloor) {
    auto result = lan::menuInput(input);
    // Stop stale movement/items until the guest sees the destination. Releasing
    // held fire here would discharge Brimstone and other charged weapons.
    if (sameFloor) {
        result.pointer = input.pointer;
        for (unsigned button = action::shootLeft; button <= action::shootDown; ++button)
            result.values[button] = input.values[button];
    }
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
    if (!paused && (input.triggered & (1u << action::menuBack))) {
        input.triggered |= 1u << action::menuPause;
        input.values[action::menuPause] = lan::maxInputValue;
    }
}
inline lan::InputFrame pausedInput(const lan::InputFrame& input) {
    lan::InputFrame result;
    result.pointer = input.pointer;
    // Menu navigation stays local. Keep held fire for charged weapons across
    // the authoritative resume boundary, without forwarding item/button edges.
    for (unsigned button = action::shootLeft; button <= action::shootDown; ++button)
        result.values[button] = input.values[button];
    return result;
}
} // namespace isaac::input
